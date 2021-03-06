#    TremAdminBot: A bot that provides some helper functions for Tremulous server administration
#    By Chris "Lakitu7" Schwarz, lakitu7@mercenariesguild.net
#
#    This file is part of TremAdminBot
#
#    TremAdminBot is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    TremAdminBot is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with TremAdminBot.  If not, see <http://www.gnu.org/licenses/>.
use common::sense;

sub
{
  my( $user, $acmdargs, $timestamp, $db ) = @_;

  unless( $acmdargs =~ /^([\w]+)/ )
  {
    replyToPlayer( $user, "^3memo:^7 commands: list, read, send, outbox, unsend, clear" );
    return;
  }

  my $memocmd = lc( $1 );

  if( $memocmd eq "send" )
  {
    my @split = shellwords( $acmdargs );
    shift( @split );
    unless( scalar @split >= 2 )
    {
      replyToPlayer( $user, "^3memo:^7 usage: memo send <name> <message>" );
      return;
    }

    my $memoname = lc( shift( @split ) );
    my $memo = join( " ", @split );
    my $memoq = $db->quote( $memo );

    my @matches;
    my $lastmatch;
    my $exact = -1;

    # by userID
    if( $memoname =~ /^\d+$/ )
    {
      my $q = $db->prepare( "SELECT userID, name FROM users WHERE userID=$memoname" );
      $q->execute( );
      if( my $ref = $q->fetchrow_hashref )
      {
        $lastmatch = $memoname;
        push( @matches, $ref );
      }
      else
      {
        replyToPlayer( $user, "^3memo:^7 unknown userID $memoname" );
        return;
      }
    }
    else
    {
      $memoname =~ tr/\"//d;
      my $memonameq = $db->quote( $memoname );
      my $memonamelq = $db->quote( "\%" . $memoname . "\%" );

      my $q = $db->prepare( "SELECT userID, name, seenTime FROM users WHERE useCount > 10 AND name LIKE ${memonamelq} AND seenTime > datetime( ${timestamp}, \'-3 months\' ) ORDER BY CASE WHEN name = ${memonameq} then 999999 else useCount END DESC LIMIT 10" );
      $q->execute;

      my $i = 0;
      while( my $ref = $q->fetchrow_hashref( ) )
      {
        $exact = $i if( $ref->{ 'name' } eq $memoname );
        $lastmatch = $ref->{ 'userID' };
        push( @matches, $ref );
        last if( $exact >= 0 );
        $i++;
      }
    }

    if( $exact >= 0 || @matches == 1 )
    {
      $exact ||= 0; # warning
      $db->do( "INSERT INTO memos (userID, sentBy, sentTime, msg) VALUES ($matches[ $exact ]{ 'userID' }, $user->{userID}, ${timestamp}, ${memoq})" );
      replyToPlayer( $user, "^3memo:^7 memo left for $matches[ $exact ]{ 'name' }" );
    }
    elsif( scalar @matches > 1 )
    {
      replyToPlayer( $user, "^3memo:^7 multiple matches. Be more specific or use userID: " );
      foreach( @matches )
      {
        replyToPlayer( $user, "^3  $_->{ 'userID' }  $_->{ 'seenTime' } ^7$_->{ 'name' }" );
      }
    }
    else
    {
      replyToPlayer( $user, "^3memo:^7 invalid memo target: ${memoname} not seen in last 3 months or at least 10 times." );
    }
  }
  elsif( $memocmd eq "list" )
  {
    my $q = $db->prepare( "SELECT memos.memoID, memos.readTime, users.name FROM memos JOIN users ON users.userID = memos.sentBy WHERE memos.userID = $user->{userID} ORDER BY memoID ASC" );
    $q->execute;

    my @memos;
    my @readMemos;
    while( my $ref = $q->fetchrow_hashref( ) )
    {
      my $name = $ref->{ 'name' };
      my $readTime = $ref->{ 'readTime' };
      my $memoID = $ref->{ 'memoID' };

      if( $readTime )
      {
        push( @readMemos, ${memoID} );
      }
      else
      {
        push( @memos, ${memoID} );
      }
    }
    my $newCount = scalar @memos;
    my $readCount = scalar @readMemos;
    replyToPlayer( $user, "^3memo:^7 You have ${newCount} new Memos: " . join( "^3,^7 ", @memos ) . ". Use /memo read <memoID>" ) if( $newCount );
    replyToPlayer( $user, "^3memo:^7 You have ${readCount} read Memos: " . join( "^3,^7 ", @readMemos ) ) if( $readCount );
    replyToPlayer( $user, "^3memo:^7 You have no memos." ) if( !$newCount && !$readCount );
  }

  elsif( $memocmd eq "read" )
  {
    my $memoID;
    unless( ( $memoID ) = $acmdargs =~ /^(?:[\w]+) ([\d]+)/ )
    {
      replyToPlayer( $user, "^3memo:^7 usage: memo read <memoID>" );
      return;
    }
    my $memoIDq = $db->quote( $memoID );

    my $q = $db->prepare( "SELECT memos.memoID, memos.sentTime, memos.msg, users.name FROM memos JOIN users ON users.userID = memos.sentBy WHERE memos.memoID = ${memoIDq} AND memos.userID = $user->{userID}" );
    $q->execute;
    if( my $ref = $q->fetchrow_hashref( ) )
    {
      my $id = $ref->{ 'memoID' };
      my $from = $ref->{ 'name' };
      my $sentTime = $ref->{ 'sentTime' };
      my $msg = $ref->{ 'msg' };

      replyToPlayer( $user, "Memo: ${id} From: ${from} Sent: ${sentTime}" );
      replyToPlayer( $user, " Msg: ${msg}" );

      $db->do( "UPDATE memos SET readTime=${timestamp} WHERE memoID=${memoIDq}" );
    }
    else
    {
      replyToPlayer( $user, "^3memo:^7: Invalid memoID: ${memoID}" );
    }
  }
  elsif( $memocmd eq "outbox" )
  {
    my $q = $db->prepare( "SELECT memos.memoID, users.name FROM memos JOIN users ON users.userID = memos.userID WHERE memos.sentBy = $user->{userID} AND memos.readTime IS NULL ORDER BY memoID ASC" );
    $q->execute;

    my @memos;
    while( my $ref = $q->fetchrow_hashref( ) )
    {
      my $name = $ref->{ 'name' };
      my $memoID = $ref->{ 'memoID' };

      push( @memos, "ID: ${memoID} To: ${name}" );
    }
    replyToPlayer( $user, "^3memo:^7 Unread Sent Memos: " . join( "^3,^7 ", @memos ) ) if( scalar @memos );
    replyToPlayer( $user, "^3memo:^7 You have no unread sent memos." ) if( ! scalar @memos );
  }
  elsif( $memocmd eq "unsend" )
  {
    my $memoID;
    unless( ( $memoID ) = $acmdargs =~ /^(?:[\w]+) ([\d]+)/ )
    {
      replyToPlayer( $user, "^3memo:^7 usage: memo unsend <memoID>" );
      return;
    }

    my $memoIDq = $db->quote( $memoID );

    my $count = $db->do( "DELETE FROM memos WHERE sentBy = $user->{userID} AND memoID = ${memoIDq}" );
    if( $count ne "0E0" )
    {
      replyToPlayer( $user, "^3memo:^7 deleted sent memo ${memoID}" );
    }
    else
    {
      replyToPlayer( $user, "^3memo:^7 invalid memoID ${memoID}" );
    }
  }
  elsif( $memocmd eq "clear" )
  {
    my $clearcmd;
    unless( ( $clearcmd ) = $acmdargs =~ /^(?:[\w]+) ([\w]+)/ )
    {
      replyToPlayer( $user, "^3memo:^7 usage: memo clear <ALL|READ>" );
      return;
    }
    $clearcmd = lc( $clearcmd );

    if( $clearcmd eq "all" )
    {
      my $count = $db->do( "DELETE FROM memos WHERE userID = $user->{userID}" );
      $count = 0 if( $count eq "0E0" );
      replyToPlayer( $user, "^3memo:^7 cleared ${count} memos" );
    }
    elsif( $clearcmd eq "read" )
    {
      my $count = $db->do( "DELETE FROM memos WHERE userID = $user->{userID} AND readTime IS NOT NULL" );
      $count = 0 if( $count eq "0E0" );
      replyToPlayer( $user, "^3memo:^7 cleared ${count} read memos" );
    }
    else
    {
      replyToPlayer( $user, "^3memo:^7 usage: memo clear <ALL|READ>" );
    }
  }
  else
  {
    replyToPlayer( $user, "^3memo:^7 commands: list, read, send, outbox, unsend, clear" );
  }
};

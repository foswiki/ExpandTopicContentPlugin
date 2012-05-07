# See bottom of file for default license and copyright information
=begin TML

---+ package ExpandTopicContentPlugin

This plugin implements the macro EXPANDTOPIC which fetches the content of a
a given topic and returns the content a bit like an INCLUDE does.

The following is done to the expanded topic.

   * If the parameter expand is set to 'create' all macros inside sections of
     type 'expandvariables' are expanded the same way, and according to the
     same rules as when a template topic is expanded when creating a new topic.
   * If the parameter expand is set to 'all' all macros are expanded in the
     scope of the expanded topic.
   * If the parameter expand is set to 'none' no macros are expanded (they will
     be later in the context of the parent topic unless encoded).
   * Defined preferences in the expanded topic are not defined in the including
     parent topic. Preferences defined in the parent are however valid in the
     expanded topic.
   * If the parameter encode is set to 'entity' the entire expanded topic is
     entity encoded so it can be contained inside a hidden html text field.
   * If the parameter encode is set to 'hidden' the EXPANDTOPIC returns nothing.
     This can be quite useful if the expanded topic contains Macros from
     plugins that either performs an action or defines macros that are
     accessible from the parent topic
     
The applications for this plugin are

   * Enable overwriting existing topics by the expanded content of a template
     topic. E.g. to create flat static base line document that can be updated
     from a template topic that contains formatted searches, INCLUDEs, and
     other macros. This is done by making a creator topic that contains
     an HTML form that targets the base line topic and contains a hidden
     input field with ..  <input type="hidden" name="text"
     value="%EXPANDTOPIC{"TemplateTopic" encode="entiry"}% />
   * INCLUDE a topic without actually including the content in the rendered
     output but take advantage of the actions a plugin takes on the included
     topic. An example can be to include a schedule created by TimeCalcPlugin
     and display selected stored time values in the parent topic.
     Note that the parent topic cannot use preferences defined in the expanded
     topic. They are only valid in content taken from the expanded topic.
     
=cut

package Foswiki::Plugins::ExpandTopicContentPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package. This should always be in the format
# $Rev: 9771 $ so that Foswiki can determine the checked-in status of the
# extension.
our $VERSION = '$Rev: 9771 $';  # Do not change this
our $RELEASE = '1.0';           # Change this. Keep it in X.Y format
our $SHORTDESCRIPTION = 'Expands all macros and expandvariables type sections of a topic and return the raw markup';
our $NO_PREFS_IN_TOPIC = 1;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin topic is in
     (usually the same as =$Foswiki::cfg{SystemWebName}=)

*REQUIRED*

Called to initialise the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using =Foswiki::Func::writeWarning= and return 0. In this case
%<nop>FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

__Note:__ Please align macro names with the Plugin name, e.g. if
your Plugin is called !FooBarPlugin, name macros FOOBAR and/or
FOOBARSOMETHING. This avoids namespace issues.

=cut

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    # Register the _EXAMPLETAG function to handle %EXAMPLETAG{...}%
    # This will be called whenever %EXAMPLETAG% or %EXAMPLETAG{...}% is
    # seen in the topic text.
    Foswiki::Func::registerTagHandler( 'EXPANDTOPIC', \&_EXPANDTOPIC );

    # Plugin correctly initialized
    return 1;
}

sub _entityEncode {
    my ( $text ) = @_;

    # encode all non-printable 7-bit chars (< \x1f),
    # except \n (\xa) and \r (\xd)
    # encode HTML special characters '>', '<', '&', ''' and '"'.
    # encode TML special characters '%', '|', '[', ']', '@', '_',
    # '*', and '='
    $text =~
      s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|\n])/'&#'.ord($1).';'/ge;
    return $text;
}

# The function used to handle the %EXAMPLETAG{...}% macro
# You would have one of these for each macro you want to process.
sub _EXPANDTOPIC {
    my($session, $params, $topic, $web, $topicObject) = @_;
    # $session  - a reference to the Foswiki session object
    #             (you probably won't need it, but documented in Foswiki.pm)
    # $params=  - a reference to a Foswiki::Attrs object containing 
    #             parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             (unnamed) parameter.
    # $topic    - name of the topic in the query
    # $web      - name of the web in the query
    # $topicObject - a reference to a Foswiki::Meta object containing the
    #             topic the macro is being rendered in (new for foswiki 1.1.x)
    # Return: the result of processing the macro. This will replace the
    # macro call in the final text.

    # For example, %EXAMPLETAG{'hamburger' sideorder="onions"}%
    # $params->{_DEFAULT} will be 'hamburger'
    # $params->{sideorder} will be 'onions'
    
    my $sourceWeb = $params->{web} || $web;
    my $sourceTopic = $params->{_DEFAULT} || $topic;
    my $encode = $params->{encode} || 'none';
    my $expand = $params->{expand} || 'all';
    
    ( $sourceWeb, $sourceTopic ) =
      Foswiki::Func::normalizeWebTopicName( $sourceWeb, $sourceTopic );
      
    my $currentWikiName = Foswiki::Func::getWikiName( );
    
    unless ( Foswiki::Func::topicExists( $sourceWeb, $sourceTopic ) ) {
        return 'Topic does not exist';
    }
    
    unless ( Foswiki::Func::checkAccessPermission( 'VIEW', $currentWikiName,
             undef, $sourceTopic, $sourceWeb ) ) {
        return 'Access to topic not allowed';
    }
    
    my ( undef, $text ) = Foswiki::Func::readTopic( $sourceWeb, $sourceTopic );
    
    # By pushing the topic context we get preferences in the expanded topics
    # set in its local context. Something you cannot do with INCLUDE
    Foswiki::Func::pushTopicContext( $sourceWeb, $sourceTopic );
    
    # Expand like creating new topic from templatetopic
    if ( $expand eq 'create' ) {
        $text = Foswiki::Func::expandVariablesOnTopicCreation( $text );
    }
    elsif ( $expand eq 'all' ) {
        $text = Foswiki::Func::expandCommonVariables( $text );
    }
    #else 'none'
    
    # It is tempting to keep the pushed context so preferences are available
    # by the parent but that creates a lot of trouble like cancelling edit
    # ends up in the expanded topic. We must pop back the topic context
    Foswiki::Func::popTopicContext;
    
    if ( $encode eq 'entity' ) {
        $text = _entityEncode( $text );
    }
    elsif ( $encode eq 'hide' ) {
        $text = '';
    }
    
    return $text;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2010 Kenneth Lavrsen and Foswiki Contributors.
 
Foswiki Contributors are listed in the AUTHORS file in the root
of this distribution. NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

# filemin-lib.pl

BEGIN { push(@INC, ".."); };
use WebminCore;
&init_config();
use Encode qw(decode encode);
use File::Basename;
use POSIX;

sub get_paths {
    %access = &get_module_acl();

    # Switch to the correct user
    if (&get_product_name() eq 'usermin') {
        # In Usermin, the module only ever runs as the connected user
        &switch_to_remote_user();
    }
    elsif ($access{'work_as_root'}) {
        # Root user, so no switching
        @remote_user_info = getpwnam('root');
    }
    elsif ($access{'work_as_user'}) {
        # A specific user
        @remote_user_info = getpwnam($access{'work_as_user'});
        @remote_user_info ||
            &error("Unix user $access{'work_as_user'} does not exist!");
        &switch_to_unix_user(\@remote_user_info);
    }
    else {
        # The Webmin user we are connected as
        &switch_to_remote_user();
    }

    # Get and check allowed paths
    @allowed_paths = split(/\s+/, $access{'allowed_paths'});
    if($remote_user_info[0] eq 'root' || $allowed_paths[0] eq '$ROOT') {
        # Assume any directory can be accessed
        $base = "/";
        @allowed_paths = ( $base );
    } else {
        @allowed_paths = map { $_ eq '$HOME' ? @remote_user_info[7] : $_ }
                             @allowed_paths;
        if (scalar(@allowed_paths == 1)) {
            $base = $allowed_paths[0];
        } else {
            $base = '/';
        }
    }
    $path = $in{'path'} ? $in{'path'} : '';
    $cwd = &simplify_path($base.$path);

    # Check that current directory is one of those that is allowed
    my $error = 1;
    for $allowed_path (@allowed_paths) {
        if (&is_under_directory($allowed_path, $cwd) ||
            $allowed_path =~ /^$cwd/) {
            $error = 0;
        }
    }
    if ($error) {
        &error(&text('notallowed', &html_escape($cwd),
                                   &html_escape(join(" , ", @allowed_paths))));
    }

    if (index($cwd, $base) == -1)
    {
        $cwd = $base;
    }

    # Initiate per user config
    $confdir = "$remote_user_info[7]/.filemin";
    if(!-e "$confdir/.config") {
        &read_file_cached("$module_root_directory/defaultuconf", \%userconfig);
    } else {
        &read_file_cached("$confdir/.config", \%userconfig);
    }
}

sub print_template {
    $template_name = @_[0];
    if (open(my $fh, '<:encoding(UTF-8)', $template_name)) {
      while (my $row = <$fh>) {
        print (eval "qq($row)");
      }
    } else {
      print "$text{'error_load_template'} '$template_name' $!";
    }
}

sub print_errors {
    my @errors = @_;
    &ui_print_header(undef, "Filemin", "");
    print $text{'errors_occured'};
    print "<ul>";
    foreach $error(@errors) {
        print("<li>$error</li>");
    }
    print "<ul>";
    &ui_print_footer("index.cgi?path=".&urlize($path), $text{'previous_page'});
}

sub print_interface {
    # Some vars for "upload" functionality
    local $upid = time().$$;
    local @remote_user_info = getpwnam($remote_user);
    local $uid = @remote_user_info[2];
    $bookmarks = get_bookmarks();

    # Set things up according to currently used theme
    if ($current_theme eq 'authentic-theme' or $current_theme eq 'bootstrap') {
        # Interface for Bootstrap 3 powered themes
        # Set icons variables
        $edit_icon = "<i class='fa fa-edit' alt='$text{'edit'}'></i>";
        $rename_icon = "<i class='fa fa-font' title='$text{'rename'}'></i>";
        $extract_icon = "<i class='fa fa-external-link' alt='$text{'extract_archive'}'></i>";
        $goto_icon = "<i class='fa fa-arrow-right' alt='$text{'goto_folder'}'></i>";
        # Add static files
        print "<script type=\"text/javascript\" src=\"unauthenticated/js/main.js\"></script>";
        print "<script type=\"text/javascript\" src=\"unauthenticated/js/chmod-calculator.js\"></script>";
        print "<script type=\"text/javascript\" src=\"unauthenticated/js/dataTables.bootstrap.js\"></script>";
        print "<script type=\"text/javascript\" src=\"unauthenticated/js/bootstrap-hover-dropdown.min.js\"></script>";
        print "<link rel=\"stylesheet\" type=\"text/css\" href=\"unauthenticated/css/style.css\" />";
        print "<link rel=\"stylesheet\" type=\"text/css\" href=\"unauthenticated/css/dataTables.bootstrap.css\" />";
        init_datatables();
        # Set "root" icon
        if($base eq '/') {
            $root_icon = "<i class='fa fa-hdd-o'></i>";
        } else {
            $root_icon = "~";
        }
        # Breadcrumbs
        print "<ol class='breadcrumb pull-left'><li><a href='index.cgi?path='>$root_icon</a></li>";
        my @breadcr = split('/', $path);
        my $cp = '';
        for(my $i = 1; $i <= scalar(@breadcr)-1; $i++) {
            chomp($breadcr[$i]);
            $cp = $cp.'/'.$breadcr[$i];
            print "<li><a href='index.cgi?path=".&urlize($cp)."'>".
		  &html_escape($breadcr[$i])."</a></li>";
        }
        print "</ol>";
        # And toolbar
        if($userconfig{'menu_style'}) {
            print_template("unauthenticated/templates/menu.html");
        } else {
            print_template("unauthenticated/templates/quicks.html");
        }
        $page = 1;
        $pagelimit = 9001; # IT'S OVER NINE THOUSAND!
        print_template("unauthenticated/templates/dialogs.html");
    } else {
        # Interface for legacy themes
        # Set icons variables
        $edit_icon = "<img src='images/icons/quick/edit.png' alt='$text{'edit'}' />";
        $rename_icon = "<img src='images/icons/quick/rename.png' alt='$text{'rename'}' />";
        $extract_icon = "<img src='images/icons/quick/extract.png' alt='$text{'extract_archive'}' />";
        $goto_icon = "<img src='images/icons/quick/go-next.png' alt='$text{'goto_folder'}'";
        # Add static files
        $head = "<link rel=\"stylesheet\" type=\"text/css\" href=\"unauthenticated/css/style.css\" />";
        $head.= "<script type=\"text/javascript\" src=\"unauthenticated/jquery/jquery.min.js\"></script>";
        $head.= "<script type=\"text/javascript\" src=\"unauthenticated/jquery/jquery-ui.min.js\"></script>";
        $head.= "<script type=\"text/javascript\" src=\"unauthenticated/js/legacy.js\"></script>";
        $head.= "<link rel=\"stylesheet\" type=\"text/css\" href=\"unauthenticated/jquery/jquery-ui.min.css\" />";
        $head.= "<script type=\"text/javascript\" src=\"unauthenticated/js/chmod-calculator.js\"></script>";
        $head.= "<link rel=\"stylesheet\" type=\"text/css\" href=\"unauthenticated/dropdown/fg.menu.css\" />";
        $head.= "<script type=\"text/javascript\" src=\"unauthenticated/dropdown/fg.menu.js\"></script>";
        print $head;
        # Set "root" icon
        if($base eq '/') {
            $root_icon = "<img src=\"images/icons/quick/drive-harddisk.png\" class=\"hdd-icon\" />";
        } else {
            $root_icon = "~";
        }
        # Legacy breadcrumbs
        print "<div id='bread' style='float: left; padding-bottom: 2px;'><a href='index.cgi?path='>$root_icon</a> / ";
        my @breadcr = split('/', $path);
        my $cp = '';
        for(my $i = 1; $i <= scalar(@breadcr)-1; $i++) {
            chomp($breadcr[$i]);
            $cp = $cp.'/'.$breadcr[$i];
            print "<a href='index.cgi?path=".&urlize($cp)."'>".
		  &html_escape($breadcr[$i])."</a> / ";
        }
        print "<br />";
        # And pagination
        $page = $in{'page'};
        $pagelimit = $userconfig{'per_page'};
        $pages = ceil((scalar(@list))/$pagelimit);
        if (not defined $page or $page > $pages) { $page = 1; }
        print "Pages: ";
        for(my $i = 1;$i <= $pages;$i++) {
            if($page eq $i) {
                print "<a class='pages active' ".
                      "href='?path=".&urlize($path).
                      "&page=".&urlize($i).
                      "&query=".&urlize($query).
                      "'>".&html_escape($i)."</a>";
            } else {
                print "<a class='pages' ".
                      "href='?path=".&urlize($path).
                      "&page=".&urlize($i).
                      "&query=".&urlize($query)."'>".&html_escape($i)."</a>";
            }
        }
        print "</div>";
        # And toolbar
        print_template("unauthenticated/templates/legacy_quicks.html");
        print_template("unauthenticated/templates/legacy_dialogs.html");
    }

    # Render current directory entries
    print &ui_form_start("", "post", undef, "id='list_form'");
    @ui_columns = (
            '<input id="select-unselect" type="checkbox" onclick="selectUnselect(this)" />',
            ''
        );
    push @ui_columns, $text{'name'};
    push @ui_columns, $text{'type'} if($userconfig{'columns'} =~ /type/);
    push @ui_columns, $text{'actions'};
    push @ui_columns, $text{'size'} if($userconfig{'columns'} =~ /size/);
    push @ui_columns, $text{'owner_user'} if($userconfig{'columns'} =~ /owner_user/);
    push @ui_columns, $text{'permissions'} if($userconfig{'columns'} =~ /permissions/);
    push @ui_columns, $text{'last_mod_time'} if($userconfig{'columns'} =~ /last_mod_time/);

    print &ui_columns_start(\@ui_columns);
    #foreach $link (@list) {
    for(my $count = 1 + $pagelimit*($page-1);$count <= $pagelimit+$pagelimit*($page-1);$count++) {
        if ($count > scalar(@list)) { last; }
        my $class = $count & 1 ? "odd" : "even";
        my $link = $list[$count - 1][0];
        $link =~ s/$cwd\///;
        $link =~ s/^\///g;
        $link = html_escape($link);
        $link = quote_escape($link);
        $link = decode('UTF-8', $link, Encode::FB_CROAK);
        $path = html_escape($path);
        $path = quote_escape($path);
        $path = decode('UTF-8', $path, Encode::FB_CROAK);

        my $type = $list[$count - 1][14];
        $type =~ s/\//\-/g;
        my $img = "images/icons/mime/$type.png";
        unless (-e $img) { $img = "images/icons/mime/unknown.png"; }
        $size = &nice_size($list[$count - 1][8]);
        $user = getpwuid($list[$count - 1][5]);
        $group = getgrgid($list[$count - 1][6]);
        $permissions = sprintf("%04o", $list[$count - 1][3] & 07777);
        $mod_time = POSIX::strftime('%Y/%m/%d - %T', localtime($list[$count - 1][10]));

        $actions = "<a class='action-link' href='javascript:void(0)' onclick='renameDialog(\"$link\")' title='$text{'rename'}' data-container='body'>$rename_icon</a>";

        if ($list[$count - 1][15] == 1) {
            $href = "index.cgi?path=".&urlize("$path/$link");
        } else {
            $href = "download.cgi?file=".&urlize($link)."&path=".&urlize($path);
            if($0 =~ /search.cgi/) {
                ($fname,$fpath,$fsuffix) = fileparse($list[$count - 1][0]);
                if($base ne '/') {
                    $fpath =~ s/^$base//g;
                }
                $actions = "$actions<a class='action-link' ".
			   "href='index.cgi?path=".&urlize($fpath)."' ".
			   "title='$text{'goto_folder'}'>$goto_icon</a>";
            }
            if (
                index($type, "text-") != -1 or
                $type eq "application-x-php" or
                $type eq "application-x-ruby" or
                $type eq "application-xml" or
                $type eq "application-javascript" or
                $type eq "application-x-shellscript" or
                $type eq "application-x-perl" or
                $type eq "application-x-yaml"
            ) {
                $actions = "$actions<a class='action-link' href='edit_file.cgi?file=".&urlize($link)."&path=".&urlize($path)."' title='$text{'edit'}' data-container='body'>$edit_icon</a>";
            }
            if (index($type, "zip") != -1 or index($type, "compressed") != -1) {
                $actions = "$actions <a class='action-link' href='extract.cgi?path=".&urlize($path)."&file=".&urlize($link)."' title='$text{'extract_archive'}' data-container='body'>$extract_icon</a> ";
            }
        }
        @row_data = (
            "<a href='$href'><img src=\"$img\"></a>",
            "<a href=\"$href\" data-filemin-path=\"$href\">$link</a>"
        );
        push @row_data, $type if($userconfig{'columns'} =~ /type/);
        push @row_data, $actions;
        push @row_data, $size if($userconfig{'columns'} =~ /size/);
        push @row_data, $user.':'.$group if($userconfig{'columns'} =~ /owner_user/);
        push @row_data, $permissions if($userconfig{'columns'} =~ /permissions/);
        push @row_data, $mod_time if($userconfig{'columns'} =~ /last_mod_time/);

        print &ui_checked_columns_row(\@row_data, "", "name", $link);
    }
    print ui_columns_end();
    print &ui_hidden("path", $path),"\n";
    print &ui_form_end();
}

sub init_datatables {
    my ($a, $b, $c);
    $a = '0, 1, 3';
    $b = '4';
    $c = '';
    if ($userconfig{'columns'} =~ /type/) {
        $a = '0, 1, 4';
        $b = '5';
    }
    if ($userconfig{'columns'} =~ /size/) {
        $c = '{ "type": "file-size", "targets": [' . $b . '] },';
    }

    if($userconfig{'disable_pagination'}) {
        $bPaginate = 'false';
    } else {
        $bPaginate = 'true';
    }
print "<script>";
print "\$( document ).ready(function() {";
print "\$.fn.dataTableExt.sErrMode = 'throw';";
print "\$('#list_form > table').dataTable({";
print "\"order\": [],";
print "\"aaSorting\": [],";
print "\"bDestroy\": true,";
print "\"bPaginate\": $bPaginate,";
print " \"fnDrawCallback\": function(oSettings) {
        if (oSettings.fnRecordsTotal() <= oSettings._iDisplayLength) {
            \$('.dataTables_paginate').hide();
        } else {
            \$('.dataTables_paginate').show();
        }
    },";
print " \"initComplete\": function() {
        \$('div.dataTables_filter input').val('').trigger('keyup');
        \$('div.dataTables_filter input').focus();
        \$(document).on('keydown', function (event) {
            var keycode = event.keyCode ? event.keyCode : event.which;
            if (!\$('input').is(':focus') && !\$('select').is(':focus') && !\$('textarea').is(':focus')) {
                if (keycode === 39) {
                    \$('.paginate_button.next').trigger('click');
                }
                if (keycode === 37) {
                    \$('.paginate_button.previous').trigger('click');
                }
            }
        });
    },";
print "\"bInfo\": false,";
print "\"destroy\": true,";
print "\"oLanguage\": {";
print "\"sSearch\": \" \"";
print "},";
print "\"columnDefs\": [ { \"orderable\": false, \"targets\": [$a] }, $c ],";
print "\"bStateSave\": true,";
print "\"iDisplayLength\": 50,";
print "});";
print "\$(\"form\").on('click', 'div.popover', function() {";
print "\$(this).prev('input').popover('hide');";
print "});";
print "});";
print "</script>";
}

sub get_bookmarks {
    $confdir = "$remote_user_info[7]/.filemin";
    if(!-e "$confdir/.bookmarks") {
        return "<li><a>$text{'no_bookmarks'}</a></li>";
    }
    my $bookmarks = &read_file_lines($confdir.'/.bookmarks', 1);
    $result = '';
    foreach $bookmark(@$bookmarks) {
        $result.= "<li><a href='index.cgi?path=".&urlize($bookmark)."'>".
		  &html_escape($bookmark)."</a><li>";
    }
    return $result;
}

1;


# Pegex::Base generated from Moos-0.10

use strict;
use warnings;
use 5.008;

my $VALID_NAME = qr{ ^ [^\W0-9] \w* $ }ix;

package Pegex::Base;

use Scalar::Util;
use Carp qw(confess);

if ($] >= 5.010) {
    require mro;
}
else {
    require MRO::Compat;
}

# our $VERSION = '0.10';

our $CAN_HAZ_XS =
    !$ENV{PERL_MOOS_XS_DISABLE} &&
    eval{ require Class::XSAccessor; Class::XSAccessor->VERSION("1.07"); 1 };

use constant default_metaclass => 'Pegex::Base::Meta::Class';
use constant default_base_class => 'Pegex::Base::Object';

sub import {
    my ($class, %args) = @_;
    # Get name of the "class" from whence "use Pegex::Base;"
    my $package = caller;

    # Turn on strict/warnings for caller
    strict->import;
    warnings->import;

    # Create/register a metaclass object for the package
    my $metaclass =
        delete $args{metaclass}
        || $class->default_metaclass;
    my $meta = $metaclass->initialize($package, %args);

    # Make calling class inherit from Pegex::Base::Object by default
    my $baseclass = exists $args{base_class}
        ? delete $args{base_class}
        : $class->default_base_class;
    extends($meta, $baseclass) if defined $baseclass;

    # Export the 'has', 'extends', and 'with' helper functions
    _export($package, has => \&has, $meta);
    _export($package, extends => \&extends, $meta);
    _export($package, with => \&with, $meta);

    # Export the 'blessed' and 'confess' functions
    _export($package, blessed => \&Scalar::Util::blessed);
    _export($package, confess => \&Carp::confess);

    # Possibly export some handy debugging stuff
    _export_xxx($package) if $ENV{PERL_MOOS_XXX};
}

sub has {
    my ($meta, $name) = splice(@_, 0, 2);
    $name = [$name] unless ref $name;
    my %args;

    # Support 2-arg shorthand:
    #     has foo => 42;
    if (@_ % 2) {
        my $default = shift;
        my $sub =
            ref($default) eq 'HASH' ? sub {+{%$default}} :
            ref($default) eq 'ARRAY' ? sub {[@$default]} :
            sub {$default};
        %args = (default => $sub);
    }
    %args = (%args, @_);

    # Add attributes to meta class object
    $meta->add_attribute($_ => \%args) for @$name;
}

sub extends {
    my ($meta, @parent) = @_;
    eval "require $_" for @parent;
    $meta->superclasses(@parent);
}

sub with {
    my ($meta, @roles) = @_;
    $meta->apply_roles(@roles);
}

sub _export {
    my ($package, $name, $code, $meta) = @_;
    if (defined $meta) {
        my $orig = $code;
        $code = sub {
            unshift @_, $meta;
            goto &$orig;
        };
    }
    no strict 'refs';
    *{"$package\::$name"} = $code;
}

sub _export_xxx {
    my ($package) = @_;
    eval "use XXX -with => 'YAML::XS'; 1" or die $@;
    no strict 'refs';
    _export($package, WWW => \&{__PACKAGE__ . '::WWW'});
    _export($package, XXX => \&{__PACKAGE__ . '::XXX'});
    _export($package, YYY => \&{__PACKAGE__ . '::YYY'});
    _export($package, ZZZ => \&{__PACKAGE__ . '::ZZZ'});
}

package Pegex::Base::Meta::Class;
use Carp qw(confess);
our @ISA = 'Pegex::Base::Object';

my $meta_class_objects = {};

sub name { $_[0]->{package} }

sub default_attribute_metaclass { 'Pegex::Base::Meta::Attribute' }

sub attribute_metaclass {
    $_[0]{attribute_metaclass};
}
__PACKAGE__->meta->add_attribute(
    attribute_metaclass => {
        is => 'ro',
        default => \&default_attribute_metaclass,
        _skip_setup => 1,
    },
);

sub initialize {
    my ($class, $package, %args) = @_;

    # Class to use to generate attribute accessors, etc
    $args{attribute_metaclass} ||= $class->default_attribute_metaclass;

    # This is a tiny version of a Pegex::Basee meta-class-object.
    # We really just need a place to keep the attributes.
    return $meta_class_objects->{$package} ||= do {
        bless {
            package => $package,
            # This isn't currently used but matches Pegex::Basee and is cheap.
            attributes => {},
            # We construct with attribute in order defined. (Unlike Pegex::Basee)
            _attributes => [],
            %args,
        }, $class;
    };
}

sub add_attribute {
    my $self = shift;
    my $name = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    push @{$self->{_attributes}}, (
        $self->{attributes}{$name} =
        $self->attribute_metaclass->new(
            name => $name,
            associated_class => $self,
            %args,
        )
    );
}

my $trace_exclude = +{
    map {($_, 1)} (
        'Some::Module some_accessor',
        'Some::Module some_other_accessor',
    )
};
sub _trace_accessor_calls {
    require Time::HiRes;
    my ($name, $accessor) = @_;
    sub {
        my ($pkg, $file, $line, $sub) = caller(0);
        unless ($trace_exclude->{"$pkg $name"}) {
            warn "$pkg $name $line\n";
            Time::HiRes::usleep(100000);
        }
        goto &$accessor;
    };
}

sub superclasses {
    no strict 'refs';
    my ($self, @supers) = @_;
    if (@supers) {
        @{"$self->{package}\::ISA"} = @supers;
    }
    return @{"$self->{package}\::ISA"};
}

sub linearized_isa {
    my $self = shift;
    my %seen;
    return grep { not $seen{$_}++ } @{ mro::get_linear_isa($self->name) };
}

sub apply_roles
{
    my ($self, @roles) = @_;
    my $package = $self->name;

    require Role::Tiny;

    # Load the role modules. (Role::Tiny would do this for us anyway.)
    Role::Tiny::_load_module($_) for @roles;

    # If any of them were Pegex::Basee roles, then Class::MOP will now be
    # available to us. Use it to detect which roles have antlers.
    if (my $class_of = 'Class::MOP'->can('class_of')) {
        # Divide list of roles into Pegex::Basee and non-Pegex::Basee.
        my (@moose, @nonmoose);
        while (@roles) {
            my $role = shift @roles;
            my $list = $class_of->($role) ? \@moose : \@nonmoose;
            push @$list, $role;
            if (ref $roles[0] eq 'HASH') {
                push @$list, shift @roles;
            }
        }
        # Apply Pegex::Basee roles
        if (@moose and my $apply = 'Pegex::Basee::Util'->can('apply_all_roles')) {
            $apply->($package, @moose);

            foreach my $role (@moose) {
                my @attributes =
                    sort { $a->insertion_order <=> $b->insertion_order }
                    map  { $role->meta->get_attribute($_) }
                    $role->meta->get_attribute_list;
                foreach my $attr ( @attributes ) {
                    my $name = $attr->name;
                    my %args = (
                        lazy        => $attr->is_lazy,
                        required    => $attr->is_required,
                        is          => $attr->{is},
                        _skip_setup => 1,
                    );
                    for my $arg (qw/ clearer predicate builder default documentation handles trigger /)
                    {
                        my $has = "has_$arg";
                        $args{$arg} = $attr->$arg if $attr->$has;
                    }
                    $self->add_attribute($name, \%args);
                }
            }
        }
        # Allow non-Pegex::Basee roles to fall through
        @roles = @nonmoose;
    }

    if (@roles) {
        'Role::Tiny'->apply_roles_to_package($package, @roles);

        foreach my $role (@roles) {
            # Moo::Role stashes its attributes here...
            my @attributes = @{ $Role::Tiny::INFO{$role}{attributes} || [] };
            while (@attributes) {
                my $name = shift @attributes;
                my %args = %{ shift @attributes };
                $args{_skip_setup} = 1;  # Moo::Role already made accessors
                $self->add_attribute($name, \%args);
            }
        }
    }
}

sub new_object {
    my ($self, $params) = @_;
    my $object = $self->_construct_instance($params);
    $object->BUILDALL($params) if $object->can('BUILDALL');
    return $object;
}

sub _construct_instance {
    my ($self, $params) = @_;
    my $instance = bless {}, $self->name;
    foreach my $attr ($self->get_all_attributes()) {
        my $name = $attr->{name};
        next if exists $instance->{$name};
        if (exists $params->{$name}) {
            $instance->{$name} = $params->{$name};
        }
        elsif (not $attr->{lazy}) {
            if (my $builder = $attr->{builder}) {
                $builder = "_build_$name"
                    if defined $builder && $builder eq "1";
                $instance->{$name} = $instance->$builder();
                next;
            }
            elsif (my $default = $attr->{default}) {
                $instance->{$name} = $default->($instance);
            }
            if ($attr->{required} and not exists $instance->{$name}) {
                confess "missing required attribute '$name'";
            }
        }
        # Triggers only fire for explicit assignment; not defaults.
        if (exists $attr->{trigger} and exists $params->{$name}) {
            $attr->{trigger}->($instance, $params->{$name});
        }
    }
    return $instance;
}

sub get_all_attributes {
    my $self = shift;
    my (@attrs, %attrs);
    for my $package ($self->linearized_isa) {
        my $meta = Pegex::Base::Meta::Class->initialize($package);
        for my $attr (@{$meta->{_attributes}}) {
            my $name = $attr->{name};
            next if $attrs{$name};
            push @attrs, ($attrs{$name} = $attr);
        }
    }
    return @attrs;
}

sub get_attribute {
    my ($self, $name) = @_;
    return $self->{attributes}{$name};
}

sub find_attribute_by_name {
    my ($self, $name) = @_;
    for ($self->get_all_attributes) {
        return $_ if $_->name eq $name;
    }
    return;
}

package Pegex::Base::Meta::Attribute;
use Carp qw(confess);
BEGIN { our @ISA = 'Pegex::Base::Object' };

__PACKAGE__->meta->add_attribute($_, { is=>'ro' })
    for qw(
        name associated_class is isa coerce does required
        weak_ref lazy trigger handles builder default clearer
        predicate documentation _skip_setup
    );

sub _is_simple {
    not (  $_[0]{builder}
        || $_[0]{default}
        || $_[0]{trigger}
        || $ENV{PERL_MOOS_ACCESSOR_CALLS}
    );
}

sub new {
    my $class = shift;
    my $self = bless $class->BUILDARGS(@_) => $class;
    $self->Pegex::Base::Object::BUILDALL;
    return $self;
}

sub BUILDARGS {
    shift;
    my $args = @_==1 ? $_[0] : +{@_};

    # Massage %args
    my $name = $args->{name};
    $args->{builder} = "_build_$name"
        if defined $args->{builder} && $args->{builder} eq "1";
    $args->{clearer} = $name =~ /^_/ ? "_clear$name" : "clear_$name"
        if defined $args->{clearer} && $args->{clearer} eq "1";
    $args->{predicate} = $name =~ /^_/ ? "_has$name" : "has_$name"
        if defined $args->{predicate} && $args->{predicate} eq "1";
    $args->{trigger} = do {
            my ($trigger, $method) = "_trigger_$name";
            sub {
                $method ||= $_[0]->can($trigger)
                    or confess "method $trigger does not exist for class ".ref($_[0]);
                goto $method;
            };
        } if defined $args->{trigger} && $args->{trigger} eq "1";
    $args->{is} = 'rw'
        unless defined $args->{is};

    return $args;
}

sub BUILD {
    my $self = shift;
    my $metaclass = $self->{associated_class} or return;

    foreach (qw( name builder predicate clearer ))
    {
        next if !exists $self->{$_};
        next if $self->{$_} =~ $VALID_NAME;
        confess sprintf(
            "invalid method name '%s' for %s",
            $self->{$_},
            $_ eq 'name' ? 'attribute' : $_,
        );
    }

    unless ( $self->{_skip_setup} ) {
        $self->_setup_accessor($metaclass);
        $self->_setup_clearer($metaclass)    if $self->{clearer};
        $self->_setup_predicate($metaclass)  if $self->{predicate};
        $self->_setup_delegation($metaclass) if $self->{handles};
    }
}

sub _setup_accessor
{
    my ($self, $metaclass) = @_;
    my $name = $self->{name};

    if ($self->_is_simple) {
        if ($Pegex::Base::CAN_HAZ_XS) {
            my $type = $self->{is} eq 'ro' ? 'getters' : 'accessors';
            return Class::XSAccessor->import(
                class => $metaclass->{package},
                $type => [$name],
            );
        }
        else {
            my $accessor = $self->{is} eq 'ro'
                ? eval qq{ sub { Carp::confess("cannot set value for read-only accessor '$name'") if \@_ > 1; \$_[0]{'$name'} } }
                : eval qq{ sub { \$#_ ? \$_[0]{'$name'} = \$_[1] : \$_[0]{'$name'} } };
            return Pegex::Base::_export($metaclass->{package}, $name, $accessor);
        }
    }

    my ($builder, $default) = map $self->{$_}, qw(builder default);
    my $accessor =
        $builder ? sub {
            $#_ ? $_[0]{$name} = $_[1] :
            exists($_[0]{$name}) ? $_[0]{$name} :
            ($_[0]{$name} = $_[0]->$builder);
        } :
        $default ? sub {
            $#_ ? $_[0]{$name} = $_[1] :
            exists($_[0]{$name}) ? $_[0]{$name} :
            ($_[0]{$name} = $default->($_[0]));
        } :
        sub {
            $#_ ? $_[0]{$name} = $_[1] : $_[0]{$name};
        };

    if ($self->{is} eq 'ro') {
        my $orig = $accessor;
        $accessor = sub {
            confess "cannot set value for read-only accessor '$name'" if @_ > 1;
            goto $orig;
        };
    }

    elsif (exists $self->{trigger}) {
        ref $self->{trigger} or confess "trigger for $name is not a reference";
        my $orig = $accessor;
        $accessor = sub {
            if (@_ > 1) {
                $self->{trigger}->(
                    @_[0, 1],
                    exists($_[0]{$name}) ? $_[0]{$name} : (),
                );
            }
            goto $orig;
        };
    }

    # Dev debug thing to trace calls to accessor subs.
    $accessor = _trace_accessor_calls($name, $accessor)
        if $ENV{PERL_MOOS_ACCESSOR_CALLS};

    # Export the accessor.
    Pegex::Base::_export($metaclass->{package}, $name, $accessor);

    return;
}

sub _setup_clearer {
    my ($self, $metaclass) = @_;
    my $name = $self->{name};

    my $clearer = $self->{clearer} or return;
    my $sub = eval qq{ sub { delete \$_[0]{'$name'} } };
    Pegex::Base::_export($metaclass->{package}, $clearer, $sub);
    return;
}

sub _setup_predicate {
    my ($self, $metaclass) = @_;
    my $name = $self->{name};

    my $predicate = $self->{predicate} or return;

    if ($Pegex::Base::CAN_HAZ_XS) {
        return Class::XSAccessor->import(
            class => $metaclass->{package},
            predicates => { $predicate => $name },
        );
    }

    my $sub = eval qq{ sub { exists \$_[0]{'$name'} } };
    Pegex::Base::_export($metaclass->{package}, $predicate, $sub);
    return;
}

sub _setup_delegation {
    my ($self, $metaclass) = @_;
    my $name = $self->{name};

    return unless exists $self->{handles};

    my %map;
    %map = %{$self->{handles}}
        if Scalar::Util::reftype($self->{handles}) eq 'HASH';
    %map = map { ;$_=>$_ } @{$self->{handles}}
        if Scalar::Util::reftype($self->{handles}) eq 'ARRAY';

    while (my ($local, $remote) = each %map) {
        for my $method ($local, $remote) {
            next if $method =~ $VALID_NAME;
            confess "invalid delegated method name '$method'";
        }
        my $sub = eval qq{ sub { shift->{'$name'}->$remote(\@_) } };
        Pegex::Base::_export($metaclass->{package}, $local, $sub);
    }
    return;
}

package Pegex::Base::Object;

sub new {
    my $class = shift;
    my $real_class = Scalar::Util::blessed($class) || $class;
    my $params = $real_class->BUILDARGS(@_);
    return Pegex::Base::Meta::Class->initialize($real_class)->new_object($params);
}

sub BUILDARGS {
    return {@_[1..$#_]};
}

sub BUILDALL {
    return unless $_[0]->can('BUILD');
    my ($self, $params) = @_;
    for my $package (reverse $self->meta->linearized_isa) {
        no strict 'refs';
        if (defined &{"$package\::BUILD"}) {
            &{"$package\::BUILD"}($self, $params);
        }
    }
}

sub dump {
    no warnings 'once';
    my $self = shift;
    require Data::Dumper;
    local $Data::Dumper::Maxdepth = shift if @_;
    Data::Dumper::Dumper $self;
}

sub meta {
    Pegex::Base::Meta::Class->initialize(Scalar::Util::blessed($_[0]) || $_[0]);
}

sub does {
    my ($self, $role) = @_;
    return 1
        if Role::Tiny::does_role($self, $role);
    return 1
        if UNIVERSAL::can('Pegex::Basee::Util', 'can')
        && Pegex::Basee::Util->can('does_role')
        && Pegex::Basee::Util::does_role($self, $role);
    return 0;
}

sub DOES {
    my ($self, $role) = @_;
    my $universal_does = UNIVERSAL->can('DOES') || UNIVERSAL->can('isa');
    $self->does($role) or $self->$universal_does($role);
}

1;


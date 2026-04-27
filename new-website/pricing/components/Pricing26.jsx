'use client';

import { Button, Tabs, TabsContent, TabsList, TabsTrigger } from '@relume_io/relume-ui';
import { BiCheck } from 'react-icons/bi';

const comparisonPlans = {
  monthly: [
    {
      name: 'Free',
      price: '$0',
      cadence: 'Forever',
      description: 'Best for getting started',
      cta: 'Get started',
    },
    {
      name: 'Pro',
      price: '$9',
      cadence: 'Per month',
      description: 'Best for power users',
      cta: 'Upgrade now',
    },
    {
      name: 'Team',
      price: 'Custom',
      cadence: 'Contact us',
      description: 'For organizations',
      cta: 'Get in touch',
    },
  ],
  yearly: [
    {
      name: 'Free',
      price: '$0',
      cadence: 'Forever',
      description: 'Best for getting started',
      cta: 'Get started',
    },
    {
      name: 'Pro',
      price: '$90',
      cadence: 'Per year (save 20%)',
      description: 'Best for power users',
      cta: 'Upgrade now',
    },
    {
      name: 'Team',
      price: 'Custom',
      cadence: 'Custom annual pricing',
      description: 'For organizations',
      cta: 'Get in touch',
    },
  ],
};

const featureCategories = [
  {
    title: 'Essentials',
    features: [
      { name: 'Email and calendar', values: [true, true, true] },
      { name: 'Basic task management', values: [true, true, true] },
      { name: '5 GB storage', values: [true, true, true] },
      { name: 'Web and mobile apps', values: [false, true, true] },
      { name: 'Privacy-first sign in', values: [false, false, true] },
    ],
  },
  {
    title: 'Intelligence',
    features: [
      { name: 'AI-powered assistant', values: [false, true, true] },
      { name: 'Smart task creation', values: [true, true, true] },
      { name: 'Email drafting help', values: [true, true, true] },
      { name: 'Day organization', values: [false, true, true] },
      { name: 'Advanced features', values: [false, false, true] },
    ],
  },
  {
    title: 'Storage',
    features: [
      { name: 'Storage capacity', values: ['5 GB', '200 GB', 'Unlimited'] },
      { name: 'Unlimited tasks', values: [true, true, true] },
      { name: 'Unlimited notes', values: [true, true, true] },
      { name: 'Priority support', values: [false, true, true] },
      { name: 'Custom integrations', values: [false, false, true] },
    ],
  },
];

function PricingFeatureCell({ value, firstColumn = false }) {
  const baseClassName =
    'flex items-center justify-center px-4 py-4 text-center font-semibold md:px-6';
  const borderClassName = firstColumn
    ? 'border-0 border-border-primary md:border-l'
    : 'border-l border-border-primary';

  if (value === true) {
    return (
      <div className={`${baseClassName} ${borderClassName}`}>
        <BiCheck className="size-6" aria-hidden="true" />
        <span className="sr-only">Included</span>
      </div>
    );
  }

  if (value === false) {
    return (
      <div className={`${baseClassName} ${borderClassName}`}>
        <span aria-hidden="true">&nbsp;</span>
        <span className="sr-only">Not included</span>
      </div>
    );
  }

  return (
    <div className={`${baseClassName} ${borderClassName}`}>
      <span>{value}</span>
    </div>
  );
}

function PricingFeatureRow({ feature }) {
  return (
    <div className="border-border-primary grid grid-cols-3 border-b md:grid-cols-[1.5fr_1fr_1fr_1fr]">
      <p className="border-border-primary col-span-3 row-span-1 border-b py-4 pr-4 md:col-span-1 md:border-0 md:pr-6">
        {feature.name}
      </p>
      {feature.values.map((value, index) => (
        <PricingFeatureCell
          key={`${feature.name}-${index}`}
          value={value}
          firstColumn={index === 0}
        />
      ))}
    </div>
  );
}

function PricingCategory({ category }) {
  return (
    <>
      <div className="border-border-primary border-b py-5">
        <h3 className="text-base font-bold leading-[1.4] md:text-xl">{category.title}</h3>
      </div>
      {category.features.map((feature) => (
        <PricingFeatureRow key={feature.name} feature={feature} />
      ))}
    </>
  );
}

function PricingPlanHeader({ plans }) {
  return (
    <div className="border-border-primary sticky top-0 grid grid-cols-3 border-b bg-white md:grid-cols-[1.5fr_1fr_1fr_1fr]">
      <div className="hidden md:block" />
      {plans.map((plan, index) => (
        <div
          key={plan.name}
          className={[
            'flex h-full flex-col justify-between px-2 py-4 sm:px-4 sm:py-6 lg:px-6 lg:py-8',
            index === 0
              ? 'border-border-primary border-0 md:border-l'
              : 'border-border-primary border-l',
          ].join(' ')}
        >
          <div>
            <h2 className="text-base font-bold leading-[1.4] md:text-xl">{plan.name}</h2>
            <div className="my-3 md:my-4">
              <p className="lg:text-10xl text-2xl font-bold leading-[1.2] sm:text-6xl md:text-9xl">
                {plan.price}
              </p>
              <p className="inline-block font-bold">
                <span>{plan.cadence}</span>
              </p>
            </div>
            <p>{plan.description}</p>
          </div>
          <div className="mt-6 md:mt-8">
            <Button title={plan.cta} className="w-full whitespace-normal px-3 py-1 sm:px-4 sm:py-3">
              {plan.cta}
            </Button>
          </div>
        </div>
      ))}
    </div>
  );
}

function PricingComparisonTable({ billingCycle }) {
  return (
    <>
      <PricingPlanHeader plans={comparisonPlans[billingCycle]} />
      {featureCategories.map((category) => (
        <PricingCategory key={category.title} category={category} />
      ))}
    </>
  );
}

export function Pricing26() {
  return (
    <section id="compare" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="mx-auto mb-8 max-w-lg text-center md:mb-10 lg:mb-12">
          <p className="mb-3 font-semibold md:mb-4">Compare</p>
          <h1 className="mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">
            What&apos;s included
          </h1>
          <p className="md:text-base">See what each plan offers you.</p>
        </div>
        <div className="w-full">
          <Tabs defaultValue="monthly">
            <TabsList className="mx-auto mb-12 flex w-fit md:mb-20">
              <TabsTrigger value="monthly">Monthly</TabsTrigger>
              <TabsTrigger value="yearly">Yearly</TabsTrigger>
            </TabsList>
            <TabsContent value="monthly">
              <PricingComparisonTable billingCycle="monthly" />
            </TabsContent>
            <TabsContent value="yearly">
              <PricingComparisonTable billingCycle="yearly" />
            </TabsContent>
          </Tabs>
        </div>
      </div>
    </section>
  );
}

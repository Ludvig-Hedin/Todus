"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@relume_io/relume-ui";
import React, { Fragment } from "react";

export function Content27() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="grid grid-cols-1 gap-y-8 lg:grid-cols-[20rem_1fr] lg:gap-x-16 xxl:gap-x-48">
          <div>
            <div className="lg:sticky lg:top-24">
              <Accordion
                type="single"
                defaultValue="aside-menu"
                className="lg:block"
                collapsible={true}
              >
                <AccordionItem value="aside-menu" className="border-none">
                  <AccordionTrigger className="flex cursor-pointer items-center justify-between gap-3 border border-border-primary px-4 py-3 lg:pointer-events-none lg:cursor-auto lg:border-none lg:p-0 [&_svg]:size-4 [&_svg]:lg:hidden">
                    <h3 className="text-lg font-bold leading-[1.4] md:text-2xl">
                      What we collect
                    </h3>
                  </AccordionTrigger>
                  <AccordionContent className="pb-0">
                    <div className="mt-3 md:mt-4">
                      <a
                        href="#heading-2"
                        className="block px-4 py-3 md:text-md"
                        style={{ marginLeft: 0 }}
                      >
                        Heading 2
                      </a>
                      <a
                        href="#heading-3"
                        className="block px-4 py-3 md:text-md"
                        style={{ marginLeft: "16px" }}
                      >
                        Heading 3
                      </a>
                      <a
                        href="#heading-4"
                        className="block px-4 py-3 md:text-md"
                        style={{ marginLeft: "32px" }}
                      >
                        Heading 4
                      </a>
                      <a
                        href="#heading-5"
                        className="block px-4 py-3 md:text-md"
                        style={{ marginLeft: "48px" }}
                      >
                        Heading 5
                      </a>
                      <a
                        href="#heading-6"
                        className="block px-4 py-3 md:text-md"
                        style={{ marginLeft: "64px" }}
                      >
                        Heading 6
                      </a>
                    </div>
                  </AccordionContent>
                </AccordionItem>
              </Accordion>
            </div>
          </div>
          <div className="max-w-lg">
            <div className="prose md:prose-md lg:prose-lg">
              <Fragment>
                <h2 id="heading-2">Heading 2</h2>
                <p>
                  <strong>
                    Dolor enim eu tortor urna sed duis nulla. Aliquam
                    vestibulum, nulla odio nisl vitae. In aliquet pellentesque
                    aenean hac vestibulum turpis mi bibendum diam. Tempor
                    integer aliquam in vitae malesuada fringilla.
                  </strong>
                </p>
                <p>
                  Mi tincidunt elit, id quisque ligula ac diam, amet. Vel etiam
                  suspendisse morbi eleifend faucibus eget vestibulum felis.
                  Dictum quis montes, sit sit. Tellus aliquam enim urna, etiam.
                  Mauris posuere vulputate arcu amet, vitae nisi, tellus
                  tincidunt. At feugiat sapien varius id.
                </p>
                <h3 id="heading-3">Heading 3</h3>
                <p>
                  Eget quis mi enim, leo lacinia pharetra, semper. Eget in
                  volutpat mollis at volutpat lectus velit, sed auctor.
                  Porttitor fames arcu quis fusce augue enim. Quis at habitant
                  diam at. Suscipit tristique risus, at donec. In turpis vel et
                  quam imperdiet. Ipsum molestie aliquet sodales id est ac
                  volutpat.
                </p>
                <p>
                  Tristique odio senectus nam posuere ornare leo metus,
                  ultricies. Blandit duis ultricies vulputate morbi feugiat cras
                  placerat elit. Aliquam tellus lorem sed ac. Montes, sed mattis
                  pellentesque suscipit accumsan. Cursus viverra aenean magna
                  risus elementum faucibus molestie pellentesque. Arcu ultricies
                  sed mauris vestibulum.
                </p>
                <h4 id="heading-4">Heading 4</h4>
                <p>
                  Morbi sed imperdiet in ipsum, adipiscing elit dui lectus.
                  Tellus id scelerisque est ultricies ultricies. Duis est sit
                  sed leo nisl, blandit elit sagittis. Quisque tristique
                  consequat quam sed. Nisl at scelerisque amet nulla purus
                  habitasse.
                </p>
                <figure>
                  <img
                    src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image-landscape.svg"
                    alt="Relume placeholder image"
                  />
                  <figcaption>Image caption goes here</figcaption>
                </figure>
                <h5 id="heading-5">Heading 5</h5>
                <p>
                  Morbi sed imperdiet in ipsum, adipiscing elit dui lectus.
                  Tellus id scelerisque est ultricies ultricies. Duis est sit
                  sed leo nisl, blandit elit sagittis. Quisque tristique
                  consequat quam sed. Nisl at scelerisque amet nulla purus
                  habitasse.
                </p>
                <blockquote>
                  "Ipsum sit mattis nulla quam nulla. Gravida id gravida ac enim
                  mauris id. Non pellentesque congue eget consectetur turpis.
                  Sapien, dictum molestie sem tempor. Diam elit, orci, tincidunt
                  aenean tempus."
                </blockquote>
                <h6 id="heading-5">Heading 6</h6>
                <p>
                  Nunc sed faucibus bibendum feugiat sed interdum. Ipsum egestas
                  condimentum mi massa. In tincidunt pharetra consectetur sed
                  duis facilisis metus. Etiam egestas in nec sed et. Quis
                  lobortis at sit dictum eget nibh tortor commodo cursus.
                </p>
              </Fragment>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

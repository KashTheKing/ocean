import Link from "@docusaurus/Link"
import useBaseUrl from "@docusaurus/useBaseUrl"
import useDocusaurusContext from "@docusaurus/useDocusaurusContext"
import CodeBlock from "@theme/CodeBlock"
import Layout from "@theme/Layout"
import React from "react"
import styles from "./index.module.css"

const FEATURES = [
	{
		title: "Infinite and animated",
		text: "Gerstner waves on a skinned EditableMesh that follows the camera: open water to the horizon, no seams, no tiling.",
	},
	{
		title: "One plugin, no code",
		text: "Install, pick a physics and a look, add addons and preview the sea live in Edit mode. Every setting is a slider with a hint.",
	},
	{
		title: "Weather and zones",
		text: "Cross-fade the whole sea between weathers, or give a bay its own. Server physics and client visuals stay in step.",
	},
	{
		title: "Boats, swimming, drowning",
		text: "Tag a part to float. Characters swim. Optional drowning with blackout or damage. Obstacles calm the water, dry regions keep it out.",
	},
	{
		title: "Scriptable",
		text: "Surface height, depth, normals, water events and weather from any script. The module is open source and MIT.",
	},
	{
		title: "Presets and lighting",
		text: "Island, Pirate Seas, Oil Rig, Great Flood, Blank. Each brings its own waves, look, Lighting and Atmosphere.",
	},
]

const SAMPLE = `local Ocean = require(game.ReplicatedStorage.Ocean)

-- server: a storm rolls in over 30 seconds
Ocean:CreateWeather("Storm", Ocean.Presets.Ocean["Pirate Seas"])
Ocean:SetWeather("Storm", 30)

-- anywhere: keep a buoy on the surface
buoy.Position = Vector3.new(x, Ocean:GetHeight(buoy.Position), z)

-- react to things going under
Ocean.WentUnderWater:Connect(function(instance)
	print(instance.Name, "went under")
end)`

function Feature({ title, text }) {
	return (
		<div className={styles.feature}>
			<h3>{title}</h3>
			<p>{text}</p>
		</div>
	)
}

function Shot({ src, caption }) {
	return (
		<figure className={styles.shot}>
			<img src={useBaseUrl(src)} alt={caption} loading="lazy" />
			<figcaption>{caption}</figcaption>
		</figure>
	)
}

export default function Home() {
	const { siteConfig } = useDocusaurusContext()
	const hero = useBaseUrl("/img/hero.jpg")
	return (
		<Layout title={siteConfig.title} description={siteConfig.tagline}>
			<header className={styles.hero} style={{ backgroundImage: `url("${hero}")` }}>
				<div className={styles.heroInner}>
					<h1 className={styles.title}>Infinite Ocean</h1>
					<p className={styles.tagline}>{siteConfig.tagline}</p>
					<div className={styles.buttons}>
						<Link className="button button--primary button--lg" to="/docs/intro">
							Get started
						</Link>
						<Link className="button button--outline button--lg" to="/api/Ocean">
							API reference
						</Link>
					</div>
				</div>
			</header>
			<main className={styles.main}>
				<section className={styles.features}>
					{FEATURES.map((f) => (
						<Feature key={f.title} {...f} />
					))}
				</section>
				<section className={styles.split}>
					<div>
						<h2>Three lines to a storm</h2>
						<p>
							Everything replicates through attributes on one ModuleScript, so a weather set on the server is the same sea on
							every client, and the server can ask where the surface is for physics.
						</p>
						<Link to="/docs/scripting">Scripting guide →</Link>
					</div>
					<CodeBlock language="lua">{SAMPLE}</CodeBlock>
				</section>
				<section className={styles.gallery}>
					<Shot src="/img/showcase-island.jpg" caption="Island: the default sea" />
					<Shot src="/img/showcase-pirate-seas.jpg" caption="Pirate Seas: rough, stylized" />
					<Shot src="/img/showcase-oil-rig.jpg" caption="Oil Rig: long realistic swell" />
					<Shot src="/img/showcase-great-flood.jpg" caption="Great Flood: walls of water" />
				</section>
				<section className={styles.cta}>
					<h2>Made by KashTheKing</h2>
					<p>
						Support, bug reports and feedback: <strong>@KashTheKing</strong> on Roblox, Discord, YouTube and X.
					</p>
				</section>
			</main>
		</Layout>
	)
}

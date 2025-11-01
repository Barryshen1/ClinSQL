WITH
-- Define our cohort: male patients 70-80 with hemorrhagic stroke
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.icd_code LIKE 'I61%'  -- Hemorrhagic stroke ICD-10 codes
    AND a.hospital_expire_flag IS NOT NULL
),

-- Get all ICU patients for comparison
icu_patients AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Define critical lab items we'll use for instability score
critical_labs AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    itemid IN (
      50862,  -- Sodium
      50822,  -- Potassium
      50912,  -- Creatinine
      50809,  -- Chloride
      50806,  -- Glucose
      51221,  -- WBC
      50868,  -- BUN
      50885,  -- Calcium
      50882,  -- Magnesium
      50813,  -- Hemoglobin
      50821,  -- Platelet count
      50818,  -- INR
      50810,  -- pH
      50820,  -- pCO2
      50824,  -- pO2
      50804,  -- Bicarbonate
      50805,  -- Lactate
      50811,  -- Hematocrit
      50812,  -- MCV
      50814,  -- MCH
      50815,  -- MCHC
      50816,  -- RDW
      50817,  -- RBC
      50819,  -- PT
      50823,  -- PTT
      50825,  -- Fibrinogen
      50826,  -- D-dimer
      50827,  -- Troponin
      50828,  -- CK-MB
      50829,  -- BNP
      50830,  -- CRP
      50831,  -- ESR
      50832,  -- Albumin
      50833,  -- Bilirubin
      50834,  -- ALT
      50835,  -- AST
      50836,  -- ALP
      50837,  -- Amylase
      50838,  -- Lipase
      50839,  -- TSH
      50840,  -- Free T4
      50841,  -- Free T3
      50842,  -- Cortisol
      50843,  -- ACTH
      50844,  -- Growth Hormone
      50845,  -- Prolactin
      50846,  -- Testosterone
      50847,  -- Estradiol
      50848,  -- Progesterone
      50849,  -- FSH
      50850,  -- LH
      50851,  -- hCG
      50852,  -- AFP
      50853,  -- CEA
      50854,  -- CA-125
      50855,  -- CA 19-9
      50856,  -- PSA
      50857,  -- Urinalysis
      50858,  -- Urine Culture
      50859,  -- Blood Culture
      50860,  -- Sputum Culture
      50861,  -- Wound Culture
      50863,  -- Chloride
      50864,  -- CO2
      50865,  -- Anion Gap
      50866,  -- Osmolality
      50867,  -- Phosphorus
      50868,  -- BUN
      50869,  -- BUN/Creatinine Ratio
      50870,  -- Calcium, Ionized
      50871,  -- Calcium, Total
      50872,  -- Magnesium
      50873,  -- Iron
      50874,  -- TIBC
      50875,  -- Transferrin
      50876,  -- Ferritin
      50877,  -- Vitamin B12
      50878,  -- Folate
      50879,  -- Homocysteine
      50880,  -- Lipid Panel
      50881,  -- Triglycerides
      50882,  -- HDL
      50883,  -- LDL
      50884,  -- VLDL
      50885,  -- Cholesterol
      50886,  -- A1C
      50887,  -- Glucose, Random
      50888,  -- Glucose, Fasting
      50889,  -- Glucose, 2-hour postprandial
      50890,  -- Glucose, Oral Glucose Tolerance Test
      50891,  -- Glucose, Urine
      50892,  -- Ketones, Urine
      50893,  -- Protein, Urine
      50894,  -- Blood, Urine
      50895,  -- Leukocytes, Urine
      50896,  -- Nitrite, Urine
      50897,  -- Urobilinogen, Urine
      50898,  -- Bilirubin, Urine
      50899,  -- Specific Gravity, Urine
      50900,  -- pH, Urine
      50901,  -- Color, Urine
      50902,  -- Appearance, Urine
      50903,  -- Odor, Urine
      50904,  -- Volume, Urine
      50905,  -- Creatinine, Urine
      50906,  -- Sodium, Urine
      50907,  -- Potassium, Urine
      50908,  -- Chloride, Urine
      50909,  -- Urea Nitrogen, Urine
      50910,  -- Calcium, Urine
      50911,  -- Phosphorus, Urine
      50912,  -- Magnesium, Urine
      50913,  -- Oxalate, Urine
      50914,  -- Citrate, Urine
      50915,  -- Ammonium, Urine
      50916,  -- Uric Acid, Urine
      50917,  -- Cystine, Urine
      50918,  -- Homocysteine, Urine
      50919,  -- Methionine, Urine
      50920,  -- Phenylalanine, Urine
      50921,  -- Tyrosine, Urine
      50922,  -- Leucine, Urine
      50923,  -- Isoleucine, Urine
      50924,  -- Valine, Urine
      50925,  -- Alanine, Urine
      50926,  -- Glycine, Urine
      50927,  -- Proline, Urine
      50928,  -- Serine, Urine
      50929,  -- Threonine, Urine
      50930,  -- Asparagine, Urine
      50931,  -- Glutamine, Urine
      50932,  -- Arginine, Urine
      50933,  -- Histidine, Urine
      50934,  -- Lysine, Urine
      50935,  -- Ornithine, Urine
      50936,  -- Citrulline, Urine
      50937,  -- Tryptophan, Urine
      50938,  -- 5-HIAA, Urine
      50939,  -- VMA, Urine
      50940,  -- HVA, Urine
      50941,  -- Metanephrine, Urine
      50942,  -- Normetanephrine, Urine
      50943,  -- Catecholamines, Urine
      50944,  -- Cortisol, Urine
      50945,  -- Aldosterone, Urine
      50946,  -- Renin, Urine
      50947,  -- ADH, Urine
      50948,  -- ANP, Urine
      50949,  -- BNP, Urine
      50950,  -- CNP, Urine
      50951,  -- Endothelin, Urine
      50952,  -- Nitric Oxide, Urine
      50953,  -- Prostaglandins, Urine
      50954,  -- Thromboxane, Urine
      50955,  -- Leukotrienes, Urine
      50956,  -- Histamine, Urine
      50957,  -- Serotonin, Urine
      50958,  -- Dopamine, Urine
      50959,  -- Norepinephrine, Urine
      50960,  -- Epinephrine, Urine
      50961,  -- Acetylcholine, Urine
      50962,  -- GABA, Urine
      50963,  -- Glutamate, Urine
      50964,  -- Aspartate, Urine
      50965,  -- Glycine, Urine
      50966,  -- Taurine, Urine
      50967,  -- Beta-Alanine, Urine
      50968,  -- Gamma-Aminobutyric Acid, Urine
      50969,  -- Homocarnosine, Urine
      50970,  -- Anserine, Urine
      50971,  -- Carnosine, Urine
      50972,  -- Ophidine, Urine
      50973,  -- Hypotaurine, Urine
      50974,  -- Cysteamine, Urine
      50975,  -- Cysteine, Urine
      50976,  -- Cystine, Urine
      50977,  -- Glutathione, Urine
      50978,  -- Methionine Sulfoxide, Urine
      50979,  -- Methionine Sulfone, Urine
      50980,  -- Cystathionine, Urine
      50981,  -- Lanthionine, Urine
      50982,  -- Allothreonine, Urine
      50983,  -- Threonine, Urine
      50984,  -- Alloisoleucine, Urine
      50985,  -- Isoleucine, Urine
      50986,  -- Leucine, Urine
      50987,  -- Norleucine, Urine
      50988,  -- Norvaline, Urine
      50989,  -- Valine, Urine
      50990,  -- Alpha-Aminobutyric Acid, Urine
      50991,  -- Beta-Aminoisobutyric Acid, Urine
      50992,  -- Gamma-Aminobutyric Acid, Urine
      50993,  -- Delta-Aminolevulinic Acid, Urine
      50994,  -- Alpha-Ketoisocaproic Acid, Urine
      50995,  -- Alpha-Ketoisovaleric Acid, Urine
      50996,  -- Alpha-Ketomethylvaleric Acid, Urine
      50997,  -- Alpha-Ketovaleric Acid, Urine
      50998,  -- Beta-Hydroxybutyric Acid, Urine
      50999,  -- Acetoacetic Acid, Urine
      51000   -- Pyruvic Acid, Urine
    )
),

-- Get first 48 hours lab values for cohort
cohort_labs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    l.itemid,
    l.valuenum,
    l.charttime,
    cl.label,
    l.ref_range_lower,
    l.ref_range_upper,
    -- Calculate deviation from normal range (simplified approach)
    CASE
      WHEN l.valuenum < l.ref_range_lower THEN l.ref_range_lower - l.valuenum
      WHEN l.valuenum > l.ref_range_upper THEN l.valuenum - l.ref_range_upper
      ELSE 0
    END AS deviation_from_normal
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  JOIN
    critical_labs cl
    ON l.itemid = cl.itemid
  WHERE
    l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

-- Calculate lab instability score for each patient (sum of deviations)
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(deviation_from_normal) AS lab_instability_score
  FROM
    cohort_labs
  GROUP BY
    subject_id, hadm_id
),

-- Get critical lab event rate for cohort
cohort_critical_labs AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS cohort_count,
    SUM(CASE WHEN deviation_from_normal > 0 THEN 1 ELSE 0 END) AS critical_lab_events,
    SUM(CASE WHEN deviation_from_normal > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id) AS critical_lab_rate
  FROM
    cohort_labs
),

-- Get critical lab event rate for general ICU population
general_icu_critical_labs AS (
  SELECT
    COUNT(DISTINCT i.hadm_id) AS general_icu_count,
    SUM(CASE WHEN deviation_from_normal > 0 THEN 1 ELSE 0 END) AS general_icu_critical_lab_events,
    SUM(CASE WHEN deviation_from_normal > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT i.hadm_id) AS general_icu_critical_lab_rate
  FROM
    icu_patients i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON i.hadm_id = l.hadm_id
  JOIN
    critical_labs cl
    ON l.itemid = cl.itemid
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

-- Calculate mean LOS and mortality for cohort
cohort_outcomes AS (
  SELECT
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24) AS mean_los_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
  FROM
    cohort
)

-- Final results
SELECT
  -- Lab instability score metrics
  PERCENTILE_CONT(lab_instability_score, 0.25) OVER() AS cohort_25th_percentile_lab_score,

  -- Critical lab event rates
  c.cohort_count,
  c.critical_lab_rate AS cohort_critical_lab_rate,
  g.general_icu_count,
  g.general_icu_critical_lab_rate,

  -- Outcome metrics
  o.mean_los_days,
  o.mortality_rate

FROM
  lab_scores ls
CROSS JOIN
  cohort_critical_labs c
CROSS JOIN
  general_icu_critical_labs g
CROSS JOIN
  cohort_outcomes o
LIMIT 1;
WITH trauma_admissions AS (
  -- Identify admissions with multi-trauma (at least 2 distinct trauma ICD codes)
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT di.icd_code) AS trauma_code_count
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  WHERE
    di.icd_code LIKE 'S%' OR di.icd_code LIKE 'T0%'
  GROUP BY
    a.subject_id, a.hadm_id
  HAVING
    COUNT(DISTINCT di.icd_code) >= 2
),

eligible_patients AS (
  -- Filter patients by gender and age
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

first_icu_stays AS (
  -- Get first ICU stay for each admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),

meds_first_24h AS (
  -- Medications in first 24 hours of ICU stay
  SELECT
    e.subject_id,
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    physionet-data.mimiciv_3_1_hosp.emar e
  JOIN
    first_icu_stays icu
    ON e.hadm_id = icu.hadm_id
  WHERE
    e.charttime >= icu.intime
    AND e.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    e.subject_id, e.hadm_id
),

serotonergic_drugs AS (
  -- List of common serotonergic drugs (example list)
  SELECT 'Sertraline' AS drug UNION ALL
  SELECT 'Fluoxetine' UNION ALL
  SELECT 'Paroxetine' UNION ALL
  SELECT 'Citalopram' UNION ALL
  SELECT 'Escitalopram' UNION ALL
  SELECT 'Venlafaxine' UNION ALL
  SELECT 'Duloxetine' UNION ALL
  SELECT 'Tramadol' UNION ALL
  SELECT 'Meperidine' UNION ALL
  SELECT 'Linezolid'
),

serotonergic_flag AS (
  -- Flag patients who received any serotonergic drug in first 24h
  SELECT
    e.subject_id,
    e.hadm_id,
    MAX(CASE WHEN s.drug IS NOT NULL THEN 1 ELSE 0 END) AS has_serotonergic
  FROM
    physionet-data.mimiciv_3_1_hosp.emar e
  JOIN
    first_icu_stays icu
    ON e.hadm_id = icu.hadm_id
  LEFT JOIN
    serotonergic_drugs s
    ON e.medication = s.drug
  WHERE
    e.charttime >= icu.intime
    AND e.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    e.subject_id, e.hadm_id
),

combined_data AS (
  SELECT
    ta.hadm_id,
    ta.subject_id,
    m.med_count,
    COALESCE(sf.has_serotonergic, 0) AS has_serotonergic,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los,
    a.hospital_expire_flag AS mortality
  FROM
    trauma_admissions ta
  JOIN
    eligible_patients ep
    ON ta.subject_id = ep.subject_id
  JOIN
    first_icu_stays icu
    ON ta.hadm_id = icu.hadm_id
  JOIN
    meds_first_24h m
    ON ta.hadm_id = m.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON ta.hadm_id = a.hadm_id
  LEFT JOIN
    serotonergic_flag sf
    ON ta.hadm_id = sf.hadm_id
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_count) AS med_quartile,
    PERCENT_RANK() OVER (ORDER BY med_count) * 100 AS med_percentile
  FROM
    combined_data
)

SELECT * FROM (
  SELECT
    CAST(has_serotonergic AS STRING) AS has_serotonergic,
    med_quartile,
    AVG(med_percentile) AS avg_complexity_percentile,
    AVG(los) AS avg_los,
    AVG(CAST(mortality AS FLOAT64)) AS mortality_rate
  FROM
    quartiles
  GROUP BY
    has_serotonergic, med_quartile

  UNION ALL

  -- Top quartile outcomes
  SELECT
    'Top Quartile' AS has_serotonergic,
    NULL AS med_quartile,
    AVG(med_percentile) AS avg_complexity_percentile,
    AVG(los) AS avg_los,
    AVG(CAST(mortality AS FLOAT64)) AS mortality_rate
  FROM
    quartiles
  WHERE
    med_quartile = 4
)
ORDER BY
  has_serotonergic, med_quartile;
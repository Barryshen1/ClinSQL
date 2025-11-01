WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS intime_icu,
    i.outtime AS outtime_icu
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),

-- Identify patients with diabetes and heart failure
dx_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(CASE WHEN d.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.long_title LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_heart_failure
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    c.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

-- Filter to only those with both conditions
filtered_cohort AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_flags d
  ON c.stay_id = d.stay_id
  WHERE d.has_diabetes = 1 AND d.has_heart_failure = 1
),

-- Identify first use of medications
med_initiations AS (
  SELECT
    fc.stay_id,
    fc.intime_icu,
    fc.outtime_icu,
    pr.drug,
    pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' THEN 'Antidiabetic'
      WHEN LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' OR LOWER(pr.drug) LIKE '%bisoprolol%' THEN 'Beta-blocker'
      WHEN LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR LOWER(pr.drug) LIKE '%torsemide%' THEN 'Loop diuretic'
      ELSE NULL
    END AS drug_class
  FROM
    filtered_cohort fc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    fc.hadm_id = pr.hadm_id
  WHERE
    pr.starttime IS NOT NULL
    AND pr.drug IS NOT NULL
),

-- Tag initiations in first 48h and last 12h
tagged_initiations AS (
  SELECT
    stay_id,
    drug_class,
    starttime,
    CASE
      WHEN starttime >= intime_icu AND starttime <= DATETIME_ADD(intime_icu, INTERVAL 48 HOUR) THEN 1
      ELSE 0
    END AS in_first_48h,
    CASE
      WHEN starttime >= DATETIME_SUB(outtime_icu, INTERVAL 12 HOUR) AND starttime <= outtime_icu THEN 1
      ELSE 0
    END AS in_last_12h
  FROM
    med_initiations
  WHERE
    drug_class IS NOT NULL
),

-- Aggregate initiation counts
init_counts AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN in_first_48h = 1 THEN stay_id END) AS first_48h_init,
    COUNT(DISTINCT CASE WHEN in_last_12h = 1 THEN stay_id END) AS last_12h_init,
    COUNT(DISTINCT stay_id) AS total_stays
  FROM
    tagged_initiations
  GROUP BY
    drug_class
)

-- Final output with percentages and net change
SELECT
  drug_class,
  ROUND(100 * first_48h_init / total_stays, 2) AS first_48h_init_rate_pct,
  ROUND(100 * last_12h_init / total_stays, 2) AS last_12h_init_rate_pct,
  ROUND(100 * (last_12h_init - first_48h_init) / total_stays, 2) AS net_change_pct
FROM
  init_counts
ORDER BY
  drug_class;
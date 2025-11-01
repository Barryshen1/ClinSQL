WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

stroke_flags AS (
  SELECT
    bc.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
            ON d.icd_code = dd.icd_code
            AND d.icd_version = dd.icd_version
        WHERE
          d.hadm_id = bc.hadm_id
          AND (
            (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('430','431','432'))
            OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) IN ('I61','I62'))
          )
      ) THEN 1
      ELSE 0
    END AS is_hemorrhagic
  FROM base_cohort bc
),

drug_orders AS (
  SELECT
    subject_id,
    hadm_id,
    LOWER(drug) AS drug_name,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'fluoxetine','sertraline','citalopram','paroxetine','escitalopram',
    'venlafaxine','duloxetine','trazodone','mirtazapine','fluvoxamine'
  )
  UNION ALL
  SELECT
    subject_id,
    hadm_id,
    LOWER(medication) AS drug_name,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE LOWER(medication) IN (
    'fluoxetine','sertraline','citalopram','paroxetine','escitalopram',
    'venlafaxine','duloxetine','trazodone','mirtazapine','fluvoxamine'
  )
),

first48h_drugs AS (
  SELECT
    bc.subject_id,
    bc.hadm_id,
    do.drug_name
  FROM stroke_flags bc
  LEFT JOIN drug_orders do
    ON bc.subject_id = do.subject_id
   AND bc.hadm_id = do.hadm_id
   AND do.starttime BETWEEN bc.admittime AND bc.admittime + INTERVAL 48 HOUR
  WHERE do.drug_name IS NOT NULL
),

complexity AS (
  SELECT
    sf.subject_id,
    sf.hadm_id,
    sf.is_hemorrhagic,
    COUNT(DISTINCT f.drug_name) AS num_serotonergic
  FROM stroke_flags sf
  LEFT JOIN first48h_drugs f
    ON sf.subject_id = f.subject_id
   AND sf.hadm_id = f.hadm_id
  GROUP BY sf.subject_id, sf.hadm_id, sf.is_hemorrhagic
),

with_categories AS (
  SELECT
    c.*,
    CASE
      WHEN num_serotonergic >= 2 THEN '>=2'
      ELSE '<2'
    END AS complexity_group
  FROM complexity c
),

quartile_cutoff AS (
  SELECT
    PERCENTILE_CONT(num_serotonergic, 0.75) OVER() AS q3
  FROM complexity
  LIMIT 1
),

flag_quartile AS (
  SELECT
    wc.subject_id,
    wc.hadm_id,
    wc.is_hemorrhagic,
    wc.num_serotonergic,
    wc.complexity_group,
    bc.admittime,
    bc.dischtime,
    bc.hospital_expire_flag,
    qc.q3,
    CASE
      WHEN wc.num_serotonergic >= qc.q3 THEN 1
      ELSE 0
    END AS top_quartile
  FROM with_categories wc
  JOIN stroke_flags bc
    ON wc.subject_id = bc.subject_id
   AND wc.hadm_id = bc.hadm_id
  CROSS JOIN quartile_cutoff qc
)

SELECT
  -- Part A: Cases vs Controls, complexity groups
  CAST(t.is_hemorrhagic AS STRING) AS is_hemorrhagic,
  t.complexity_group,
  COUNT(1) AS n_patients,
  ROUND(AVG(TIMESTAMP_DIFF(t.dischtime, t.admittime, HOUR) / 24), 1) AS avg_hosp_LOS_days,
  ROUND(AVG(t.hospital_expire_flag) * 100, 1) AS mortality_pct
FROM flag_quartile t
GROUP BY 1, 2

UNION ALL

SELECT
  -- Part B: Top‐quartile complexity overall
  'top_quartile' AS is_hemorrhagic,
  '>=Q3' AS complexity_group,
  COUNT(1) AS n_patients,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24), 1) AS avg_hosp_LOS_days,
  ROUND(AVG(hospital_expire_flag) * 100, 1) AS mortality_pct
FROM flag_quartile
WHERE top_quartile = 1;
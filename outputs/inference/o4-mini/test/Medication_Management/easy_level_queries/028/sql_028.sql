WITH
-- 1. Base admissions for women aged 44-54
female_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

-- 2. Antiplatelet prescriptions within those admissions
apl_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    CASE
      WHEN LOWER(drug) LIKE '%aspirin%' THEN 'aspirin'
      WHEN LOWER(drug) LIKE '%clopidogrel%' THEN 'p2y12'
      WHEN LOWER(drug) LIKE '%ticagrelor%' THEN 'p2y12'
      WHEN LOWER(drug) LIKE '%prasugrel%' THEN 'p2y12'
      ELSE NULL
    END AS apl_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%aspirin%'
    OR LOWER(drug) LIKE '%clopidogrel%'
    OR LOWER(drug) LIKE '%ticagrelor%'
    OR LOWER(drug) LIKE '%prasugrel%'
),

-- 3. DAPT admissions: require at least one aspirin and one P2Y12 prescription overlapping
dapt_adms AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    apl_prescriptions AS a
    JOIN apl_prescriptions AS b
      ON a.subject_id = b.subject_id
      AND a.hadm_id    = b.hadm_id
      AND a.apl_class = 'aspirin'
      AND b.apl_class = 'p2y12'
      -- overlap condition
      AND a.starttime <= b.stoptime
      AND b.starttime <= a.stoptime
    JOIN female_adms AS f
      ON a.subject_id = f.subject_id
      AND a.hadm_id    = f.hadm_id
),

-- 4. All antiplatelet prescriptions for the DAPT cohort
dapt_pres_durations AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    apl_prescriptions AS p
    JOIN dapt_adms AS d
      ON p.subject_id = d.subject_id
      AND p.hadm_id    = d.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND DATE_DIFF(p.stoptime, p.starttime, DAY) >= 0
)

-- 5. Compute the standard deviation of prescription durations
SELECT
  STDDEV_POP(duration_days) AS sd_duration_days
FROM
  dapt_pres_durations;
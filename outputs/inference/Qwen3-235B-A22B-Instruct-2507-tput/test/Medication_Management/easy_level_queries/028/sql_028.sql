WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND a.admittime IS NOT NULL
),
filtered_patients AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    patient_admissions
  WHERE
    age_at_admit BETWEEN 44 AND 54
),
antiplatelet_drugs AS (
  SELECT
    hadm_id,
    drug,
    starttime,
    stoptime,
    LOWER(drug) AS drug_clean
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE
    LOWER(drug) LIKE '%aspirin%'
    OR LOWER(drug) LIKE '%clopidogrel%'
    OR LOWER(drug) LIKE '%ticagrelor%'
    OR LOWER(drug) LIKE '%prasugrel%'
    OR LOWER(drug) LIKE '%dipyridamole%'
    OR LOWER(drug) LIKE '%abciximab%'
    OR LOWER(drug) LIKE '%eptifibatide%'
    OR LOWER(drug) LIKE '%tirofiban%'
),
dapt_hadm AS (
  -- Find hospitalizations with both aspirin and another antiplatelet
  SELECT
    hadm_id
  FROM
    antiplatelet_drugs
  GROUP BY
    hadm_id
  HAVING
    SUM(CASE WHEN drug_clean LIKE '%aspirin%' THEN 1 ELSE 0 END) >= 1
    AND SUM(CASE WHEN drug_clean NOT LIKE '%aspirin%' THEN 1 ELSE 0 END) >= 1
),
dapt_antiplatelet_durations AS (
  SELECT
    ad.hadm_id,
    ad.drug,
    ad.starttime,
    ad.stoptime,
    DATETIME_DIFF(ad.stoptime, ad.starttime, HOUR) / 24.0 AS duration_days
  FROM
    antiplatelet_drugs ad
  INNER JOIN
    dapt_hadm dapt
  ON
    ad.hadm_id = dapt.hadm_id
  WHERE
    ad.starttime IS NOT NULL
    AND ad.stoptime IS NOT NULL
    AND ad.starttime <= ad.stoptime
)
SELECT
  ROUND(STDDEV(duration_days), 4) AS sd_duration_days
FROM
  dapt_antiplatelet_durations;
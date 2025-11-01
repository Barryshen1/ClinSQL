WITH antiplatelet_rx AS (
  SELECT
    subject_id,
    hadm_id,
    LOWER(drug) AS drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%aspirin%'
    OR LOWER(drug) LIKE '%clopidogrel%'
    OR LOWER(drug) LIKE '%prasugrel%'
    OR LOWER(drug) LIKE '%ticagrelor%'
    OR LOWER(drug) LIKE '%ticlopidine%'
),
dapt_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM (
    SELECT
      subject_id,
      hadm_id,
      COUNT(DISTINCT drug) AS num_antiplatelets
    FROM
      antiplatelet_rx
    GROUP BY
      subject_id,
      hadm_id
  )
  WHERE
    num_antiplatelets >= 2
),
eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
cohort_icustays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.los,
    ROW_NUMBER() OVER (PARTITION BY ic.subject_id ORDER BY ic.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN
    dapt_admissions d
    ON ic.subject_id = d.subject_id
    AND ic.hadm_id = d.hadm_id
  JOIN
    eligible_patients e
    ON ic.subject_id = e.subject_id
)
SELECT
  AVG(los) AS avg_icudos_days
FROM
  cohort_icustays
WHERE
  rn = 1;
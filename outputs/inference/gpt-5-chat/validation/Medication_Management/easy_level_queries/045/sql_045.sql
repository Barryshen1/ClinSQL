WITH dapt_admissions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON pr.subject_id = pa.subject_id
  WHERE pa.gender = 'M'
    AND pa.anchor_age BETWEEN 57 AND 67
    AND LOWER(pr.drug) LIKE '%aspirin%' -- aspirin
    OR LOWER(pr.drug) LIKE '%clopidogrel%' -- p2y12 inhibitors
    OR LOWER(pr.drug) LIKE '%prasugrel%'
    OR LOWER(pr.drug) LIKE '%ticagrelor%'
  GROUP BY pr.subject_id, pr.hadm_id
  HAVING
    COUNTIF(LOWER(pr.drug) LIKE '%aspirin%') > 0
    AND COUNTIF(LOWER(pr.drug) LIKE '%clopidogrel%'
             OR LOWER(pr.drug) LIKE '%prasugrel%'
             OR LOWER(pr.drug) LIKE '%ticagrelor%') > 0
),
dapt_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN dapt_admissions da
    ON pr.subject_id = da.subject_id
    AND pr.hadm_id = da.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.drug) LIKE '%aspirin%'
     OR LOWER(pr.drug) LIKE '%clopidogrel%'
     OR LOWER(pr.drug) LIKE '%prasugrel%'
     OR LOWER(pr.drug) LIKE '%ticagrelor%'
)
SELECT
  q[2] AS q1,
  q[4] AS q3,
  q[4] - q[2] AS iqr
FROM (
  SELECT APPROX_QUANTILES(duration_days, 4) AS q
  FROM dapt_prescriptions
  WHERE duration_days > 0
);
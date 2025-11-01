WITH antiplatelet_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    LOWER(p.drug) IN ('aspirin', 'acetylsalicylic acid', 'clopidogrel', 'ticagrelor', 'prasugrel')
    AND p.stoptime IS NOT NULL
),
patient_drug_pairs AS (
  SELECT
    ap1.subject_id,
    ap1.hadm_id,
    MAX(CASE WHEN LOWER(ap1.drug) IN ('aspirin', 'acetylsalicylic acid') THEN 1 ELSE 0 END) AS has_aspirin,
    MAX(CASE WHEN LOWER(ap1.drug) IN ('clopidogrel', 'ticagrelor', 'prasugrel') THEN 1 ELSE 0 END) AS has_p2y12
  FROM
    antiplatelet_prescriptions ap1
  GROUP BY
    ap1.subject_id, ap1.hadm_id
  HAVING
    has_aspirin = 1 AND has_p2y12 = 1
),
filtered_patients AS (
  SELECT
    pt.subject_id,
    pt.anchor_age,
    pt.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 64 AND 74
),
valid_prescriptions AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.drug,
    ap.duration_days
  FROM
    antiplatelet_prescriptions ap
  INNER JOIN
    patient_drug_pairs pdp
    ON ap.subject_id = pdp.subject_id AND ap.hadm_id = pdp.hadm_id
  INNER JOIN
    filtered_patients fp
    ON ap.subject_id = fp.subject_id
)
SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM
  valid_prescriptions;
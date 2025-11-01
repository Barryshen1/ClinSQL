WITH eligible_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    a.admittime,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  WHERE (LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%')
    AND UPPER(pat.gender) = 'M'
    AND (CAST(pat.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) BETWEEN 58 AND 68
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
)

SELECT APPROX_MEDIAN(TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0) AS median_duration_days
FROM eligible_prescriptions;
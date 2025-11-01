WITH ace_prescriptions AS (
  SELECT
    p.subject_id,
    pres.drug,
    pres.starttime,
    pres.stoptime,
    DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON p.subject_id = pres.subject_id AND a.hadm_id = pres.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND REGEXP_CONTAINS(LOWER(pres.drug), r'lisinopril|enalapril|captopril|ramipril|quinapril|perindopril|benazepril|fosinopril|trandolapril')
    AND pres.starttime >= a.admittime
    AND pres.stoptime <= a.dischtime
    AND pres.stoptime IS NOT NULL
    AND pres.starttime < pres.stoptime
)
SELECT
  STDDEV(duration_days) AS sd_duration_days
FROM ace_prescriptions;
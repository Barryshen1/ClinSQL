SELECT
  AVG(LOS_days) AS avg_hospital_los_days
FROM (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND dx.seq_num = 1  -- primary diagnosis
    AND (
         (dx.icd_version = 9 AND (
             dx.icd_code LIKE '410%' OR
             dx.icd_code LIKE '411%'
         ))
         OR
         (dx.icd_version = 10 AND (
             dx.icd_code LIKE 'I20%' OR
             dx.icd_code LIKE 'I21%' OR
             dx.icd_code LIKE 'I22%' OR
             dx.icd_code LIKE 'I24%'
         ))
    )
    AND adm.dischtime IS NOT NULL
);
WITH patient_age AS (
  SELECT p.subject_id, p.gender, 
         p.anchor_age + DATE_DIFF(DATE(a.admittime), DATE_TRUNC(DATE(p.anchor_year, 1, 1), YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
pneumonia_patients AS (
  SELECT DISTINCT a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Pneumonia%'
),
first_icu_stay AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime,
         ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS icu_stay_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
icu_los AS (
  SELECT pa.subject_id, pa.age_at_admission, 
         DATETIME_DIFF(fis.outtime, fis.intime, HOUR) / 24 AS icu_los_days
  FROM patient_age pa
  JOIN pneumonia_patients pp ON pa.subject_id = pp.subject_id
  JOIN first_icu_stay fis ON pa.subject_id = fis.subject_id
  WHERE pa.gender = 'M' AND pa.age_at_admission BETWEEN 43 AND 53 AND fis.icu_stay_num = 1
)
SELECT APPROX_QUANTILES(icu_los_days, 100)[OFFSET(25)] AS percentile_25_icu_los
FROM icu_los;
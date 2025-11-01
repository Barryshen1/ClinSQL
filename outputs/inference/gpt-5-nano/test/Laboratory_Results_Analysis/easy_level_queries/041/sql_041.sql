WITH male_pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcode
    ON diag.icd_code = dcode.icd_code AND diag.icd_version = dcode.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
    AND LOWER(dcode.long_title) LIKE '%pneumonia%'
)
SELECT STDDEV_SAMP(creat_mean) AS sd_first24h_creatinine
FROM (
  SELECT m.hadm_id, AVG(le.valuenum) AS creat_mean
  FROM male_pneumonia_admissions AS m
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON m.hadm_id = a.hadm_id AND m.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND LOWER(dli.label) LIKE '%creatinine%'
  GROUP BY m.hadm_id
) AS per_admission_means;
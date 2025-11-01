WITH pneumonia_admissions AS (
  SELECT DISTINCT 
    ad.subject_id,
    ad.hadm_id,
    ad.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code 
    AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND ad.admission_type != 'NEWBORN'
    AND ad.hospital_expire_flag = 0
    AND diag.icd_version = '10'
    AND diag.icd_code LIKE 'J1%'
),
creatinine_labs AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN pneumonia_admissions pa
    ON le.subject_id = pa.subject_id 
    AND le.hadm_id = pa.hadm_id
  WHERE li.itemid = 50912::INT64  -- Serum Creatinine
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND le.charttime >= pa.admittime
    AND le.charttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 1 DAY)
)
SELECT 
  STDDEV_POP(avg_creatinine) AS sd_average_serum_creatinine
FROM (
  SELECT 
    hadm_id,
    AVG(valuenum) AS avg_creatinine
  FROM creatinine_labs
  GROUP BY hadm_id
  HAVING avg_creatinine IS NOT NULL
);
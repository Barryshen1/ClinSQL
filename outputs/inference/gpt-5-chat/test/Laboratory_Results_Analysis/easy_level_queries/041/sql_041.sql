WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code
   AND dx.icd_version = d_dx.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND UPPER(d_dx.long_title) LIKE '%PNEUMONIA%'
)
, creatinine_in_24h AS (
  SELECT pa.subject_id, pa.hadm_id,
         AVG(le.valuenum) AS avg_creatinine_24h
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE le.valuenum IS NOT NULL
    AND UPPER(di.label) = 'CREATININE'
    AND di.fluid = 'Blood'
    AND le.charttime >= pa.admittime
    AND le.charttime < pa.admittime + INTERVAL 24 HOUR
  GROUP BY pa.subject_id, pa.hadm_id
)
SELECT STDDEV_SAMP(avg_creatinine_24h) AS sd_avg_creatinine_24h
FROM creatinine_in_24h;
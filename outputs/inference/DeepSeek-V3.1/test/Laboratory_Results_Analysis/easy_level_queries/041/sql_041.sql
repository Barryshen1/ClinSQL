WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J18%') OR
      (diag.icd_version = 9 AND (diag.icd_code LIKE '48%' OR diag.icd_code LIKE '507%'))
    )
),
creatinine_first_24h AS (
  SELECT pa.hadm_id, AVG(le.valuenum) AS avg_creatinine
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pa.hadm_id = adm.hadm_id AND pa.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id AND pa.subject_id = le.subject_id
  WHERE le.itemid = 50912  -- Serum creatinine
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
  GROUP BY pa.hadm_id
)
SELECT STDDEV(avg_creatinine) AS sd_avg_creatinine
FROM creatinine_first_24h;
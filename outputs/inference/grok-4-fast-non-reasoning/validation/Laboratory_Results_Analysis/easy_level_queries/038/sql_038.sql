WITH stroke_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 50
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'
    AND a.hospital_expire_flag = 0  -- Exclude immediate deaths
)
SELECT MIN(l.valuenum) AS min_hemoglobin_g_per_dl
FROM stroke_admissions sa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON sa.hadm_id = l.hadm_id
WHERE l.itemid IN (51221, 51222)
  AND l.valuenum IS NOT NULL
  AND l.valueuom = 'g/dL'
  AND l.charttime >= sa.admittime
  AND l.charttime <= DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR);
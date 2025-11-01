WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
  AND p.anchor_age = 95
  AND icd.long_title LIKE '%Pneumonia%'
),
peak_creatinine AS (
  SELECT l.hadm_id, MAX(l.valuenum) AS peak_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Creatinine'
  AND l.hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
  GROUP BY l.hadm_id
)
SELECT STDDEV(peak_creatinine) AS std_dev_peak_creatinine
FROM peak_creatinine;
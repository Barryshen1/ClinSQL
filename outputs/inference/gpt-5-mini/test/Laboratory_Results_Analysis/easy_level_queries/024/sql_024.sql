WITH sepsis_admissions AS (
  -- admissions with any diagnosis whose long_title mentions "sepsis"
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%sepsis%'
),

admission_platelets AS (
  -- first platelet lab within 24 hours of admission for each hadm_id
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND LOWER(li.label) LIKE '%platelet%'
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
)

SELECT
  STDDEV_SAMP(ap.valuenum) AS sd_platelet_count,
  COUNT(*) AS n_admissions
FROM admission_platelets ap
JOIN sepsis_admissions s
  ON ap.hadm_id = s.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ap.subject_id = p.subject_id
WHERE ap.rn = 1
  AND p.gender = 'M';
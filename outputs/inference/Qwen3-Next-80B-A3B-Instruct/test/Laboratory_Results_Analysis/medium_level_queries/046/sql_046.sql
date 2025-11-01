WITH amipatients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,  -- Fixed: hadm_id is from admissions table, not patients
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),
first_troponin AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.anchor_age,
    ap.admittime,
    ap.dischtime,
    le.valuenum AS troponin_t,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime) AS rn
  FROM amipatients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ap.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
initial_troponin_filtered AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age,
    admittime,
    dischtime,
    troponin_t
  FROM first_troponin
  WHERE rn = 1
)
SELECT
  COUNT(*) AS N,
  AVG(anchor_age) AS mean_age,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  AVG(troponin_t) AS mean_troponin,
  STDDEV(troponin_t) AS std_troponin,
  MIN(troponin_t) AS min_troponin,
  MAX(troponin_t) AS max_troponin
FROM initial_troponin_filtered itf
WHERE itf.troponin_t > (
  SELECT PERCENTILE_CONT(troponin_t, 0.99) 
  FROM initial_troponin_filtered
);
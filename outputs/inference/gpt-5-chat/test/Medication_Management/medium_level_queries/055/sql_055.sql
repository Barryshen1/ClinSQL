WITH t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      -- ICD-10 E11.x
      (d.icd_version = 10 AND dd.long_title LIKE 'Type 2 diabetes%')
      OR
      -- ICD-9 250.x0 or 250.x2
      (d.icd_version = 9 AND d.icd_code LIKE '250%' AND SUBSTR(d.icd_code,5,1) IN ('0','2'))
  )
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      (d.icd_version = 10 AND dd.long_title LIKE 'Heart failure%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
  )
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND a.hadm_id IN (SELECT hadm_id FROM t2dm_hadm)
    AND a.hadm_id IN (SELECT hadm_id FROM hf_hadm)
),
rx AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         pr.starttime, LOWER(pr.drug) AS drug
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),
rx_window AS (
  SELECT subject_id, hadm_id,
         CASE 
           WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 72 HOUR) THEN 'first72h'
           WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 'final48h'
         END AS `window`,
         CASE 
           WHEN drug LIKE '%glargine%' OR drug LIKE '%detemir%' OR drug LIKE '%nph%' OR drug LIKE '%degludec%' 
             THEN 'basal'
           WHEN drug LIKE '%lispro%' OR drug LIKE '%aspart%' OR drug LIKE '%glulisine%' OR 
                drug LIKE '%regular insulin%' THEN 'bolus'
           WHEN drug LIKE '%sliding%' THEN 'sliding'
           ELSE NULL
         END AS regimen
  FROM rx
),
rx_flags AS (
  SELECT hadm_id, `window`,
         MAX(CASE WHEN regimen = 'basal' THEN 1 ELSE 0 END) AS basal_flag,
         MAX(CASE WHEN regimen = 'bolus' THEN 1 ELSE 0 END) AS bolus_flag,
         MAX(CASE WHEN regimen = 'sliding' THEN 1 ELSE 0 END) AS sliding_flag
  FROM rx_window
  WHERE `window` IS NOT NULL AND regimen IS NOT NULL
  GROUP BY hadm_id, `window`
),
rx_regimen_window AS (
  SELECT hadm_id, `window`,
         basal_flag,
         bolus_flag,
         sliding_flag,
         CASE WHEN basal_flag = 1 AND bolus_flag = 1 THEN 1 ELSE 0 END AS basal_bolus_flag
  FROM rx_flags
),
counts AS (
  SELECT `window`,
         COUNT(DISTINCT hadm_id) AS n_total,
         SUM(basal_flag) AS n_basal,
         SUM(bolus_flag) AS n_bolus,
         SUM(basal_bolus_flag) AS n_basal_bolus,
         SUM(sliding_flag) AS n_sliding
  FROM rx_regimen_window
  GROUP BY `window`
),
percents AS (
  SELECT 
    `window`,
    (n_basal / n_total) * 100 AS pct_basal,
    (n_bolus / n_total) * 100 AS pct_bolus,
    (n_basal_bolus / n_total) * 100 AS pct_basal_bolus,
    (n_sliding / n_total) * 100 AS pct_sliding
  FROM counts
),
final AS (
  SELECT 
    f72.pct_basal AS first72_basal,
    f48.pct_basal AS final48_basal,
    (f48.pct_basal - f72.pct_basal) AS diff_basal,
    f72.pct_bolus AS first72_bolus,
    f48.pct_bolus AS final48_bolus,
    (f48.pct_bolus - f72.pct_bolus) AS diff_bolus,
    f72.pct_basal_bolus AS first72_basal_bolus,
    f48.pct_basal_bolus AS final48_basal_bolus,
    (f48.pct_basal_bolus - f72.pct_basal_bolus) AS diff_basal_bolus,
    f72.pct_sliding AS first72_sliding,
    f48.pct_sliding AS final48_sliding,
    (f48.pct_sliding - f72.pct_sliding) AS diff_sliding
  FROM percents f72
  JOIN percents f48
    ON f72.`window` = 'first72h' AND f48.`window` = 'final48h'
)
SELECT * FROM final;
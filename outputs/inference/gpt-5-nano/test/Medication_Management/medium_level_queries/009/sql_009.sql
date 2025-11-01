WITH eligible AS (
  -- Admissions for males 68-78 with diabetes and acute HF (same admission)
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  -- Diabetes diagnosis in this admission
  JOIN (
    SELECT DISTINCT di.subject_id, di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%diabetes%'
  ) AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  -- Acute HF diagnosis in this admission
  JOIN (
    SELECT DISTINCT di.subject_id, di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%acute%' AND LOWER(dd.long_title) LIKE '%heart failure%'
  ) AS h
    ON a.subject_id = h.subject_id AND a.hadm_id = h.hadm_id
  -- Demographics: age and sex
  WHERE (p.anchor_age >= 68 AND p.anchor_age <= 78)
    AND (UPPER(p.gender) IN ('M','MALE'))
    -- Ensure final 24h is well-defined
    AND a.dischtime IS NOT NULL
),

med_events AS (
  -- Classify pharmacy rows into insulin vs oral and compute window containments per admission
  SELECT e.subject_id,
         e.hadm_id,
         e.admittime,
         e.dischtime,
         MAX(CASE
               WHEN ph.starttime >= e.admittime
                    AND ph.starttime < TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND ph_class = 'insulin'
               THEN 1 ELSE 0
           END) AS insulin_w1,
         MAX(CASE
               WHEN ph.starttime >= e.admittime
                    AND ph.starttime < TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND ph_class = 'oral'
               THEN 1 ELSE 0
           END) AS oral_w1,
         MAX(CASE
               WHEN ph.starttime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR)
                    AND ph.starttime < e.dischtime
                    AND ph_class = 'insulin'
               THEN 1 ELSE 0
           END) AS insulin_w2,
         MAX(CASE
               WHEN ph.starttime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR)
                    AND ph.starttime < e.dischtime
                    AND ph_class = 'oral'
               THEN 1 ELSE 0
           END) AS oral_w2
  FROM eligible e
  LEFT JOIN (
    SELECT subject_id,
           hadm_id,
           starttime,
           CASE
             -- Insulin
             WHEN LOWER(medication) LIKE '%insulin%' THEN 'insulin'
             -- Common oral antidiabetics
             WHEN LOWER(medication) LIKE '%metformin%'
              OR LOWER(medication) LIKE '%glyburide%'
              OR LOWER(medication) LIKE '%glipizide%'
              OR LOWER(medication) LIKE '%glimepiride%'
              OR LOWER(medication) LIKE '%pioglitazone%'
              OR LOWER(medication) LIKE '%rosiglitazone%'
              OR LOWER(medication) LIKE '%sitagliptin%'
              OR LOWER(medication) LIKE '%linagliptin%'
              OR LOWER(medication) LIKE '%dapagliflozin%'
              OR LOWER(medication) LIKE '%empagliflozin%'
              OR LOWER(medication) LIKE '%canagliflozin%'
              OR LOWER(medication) LIKE '%ertugliflozin%'
              THEN 'oral'
             ELSE NULL
           END AS ph_class
    FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  ) ph
    ON ph.subject_id = e.subject_id
   AND ph.hadm_id = e.hadm_id
  GROUP BY e.subject_id, e.hadm_id, e.admittime, e.dischtime
)

SELECT
  'first_24h' AS window_label,
  ROUND(100.0 * SUM(insulin_w1) / NULLIF(COUNT(*), 0), 2) AS insulin_rate_pct,
  ROUND(100.0 * SUM(oral_w1) / NULLIF(COUNT(*), 0), 2) AS oral_rate_pct,
  ROUND(100.0 * (SUM(insulin_w1) - SUM(oral_w1)) / NULLIF(COUNT(*), 0), 2) AS diff_pp
FROM med_events
UNION ALL
SELECT
  'final_24h' AS window_label,
  ROUND(100.0 * SUM(insulin_w2) / NULLIF(COUNT(*), 0), 2) AS insulin_rate_pct,
  ROUND(100.0 * SUM(oral_w2) / NULLIF(COUNT(*), 0), 2) AS oral_rate_pct,
  ROUND(100.0 * (SUM(insulin_w2) - SUM(oral_w2)) / NULLIF(COUNT(*), 0), 2) AS diff_pp
FROM med_events;
WITH cohort_hadm AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d1
    ON d1.subject_id = a.subject_id AND d1.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
    ON d2.subject_id = a.subject_id AND d2.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND di1.long_title LIKE '%Type 2 diabetes%'
    AND di2.long_title LIKE '%Heart failure%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 48*3600
),
first_window AS (
  -- First 48 hours after admission
  SELECT h.hadm_id,
         COUNT(pr.drug) AS total_events,
         SUM(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_count,
         SUM(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 1 ELSE 0 END) AS oral_count
  FROM cohort_hadm AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = h.subject_id
   AND pr.hadm_id = h.hadm_id
   AND pr.starttime >= h.admittime
   AND pr.starttime <= TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
  GROUP BY h.hadm_id
),
final_window AS (
  -- Final 24 hours before discharge
  SELECT h.hadm_id,
         COUNT(pr.drug) AS total_events_f,
         SUM(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_count_f,
         SUM(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 1 ELSE 0 END) AS oral_count_f
  FROM cohort_hadm AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = h.subject_id
   AND pr.hadm_id = h.hadm_id
   AND pr.starttime < h.dischtime
   AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(h.dischtime, INTERVAL 24 HOUR))
  GROUP BY h.hadm_id
)
SELECT 'First 48 hours' AS window_label,
       COALESCE(100 * SUM(f.insulin_count) / NULLIF(SUM(f.total_events), 0), 0) AS insulin_pct,
       COALESCE(100 * SUM(f.oral_count) / NULLIF(SUM(f.total_events), 0), 0) AS oral_pct
FROM first_window f
UNION ALL
SELECT 'Final 24 hours' AS window_label,
       COALESCE(100 * SUM(ff.insulin_count_f) / NULLIF(SUM(ff.total_events_f), 0), 0) AS insulin_pct,
       COALESCE(100 * SUM(ff.oral_count_f) / NULLIF(SUM(ff.total_events_f), 0), 0) AS oral_pct
FROM final_window ff;
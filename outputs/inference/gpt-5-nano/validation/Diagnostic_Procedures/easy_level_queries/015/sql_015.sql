WITH
  -- Subset of patients who are male and aged 45-55
  male_45_55 AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 45 AND 55
  ),
  -- Distinct CABG-admission events (subject_id, hadm_id)
  cabg_events AS (
    SELECT DISTINCT p.subject_id, p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
      ON p.icd_code = d.icd_code
     AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%cabg%'
       OR LOWER(d.long_title) LIKE '%coronary artery bypass graft%'
  ),
  -- Per-patient CABG counts (0 if none)
  cabg_counts AS (
    SELECT m.subject_id,
           COUNT(DISTINCT c.hadm_id) AS cabg_count
    FROM male_45_55 AS m
    LEFT JOIN cabg_events AS c
      ON m.subject_id = c.subject_id
    GROUP BY m.subject_id
  )
SELECT
  -- 25th percentile of the per-patient CABG counts
  CAST( (APPROX_QUANTILES(cabg_count, 4))[OFFSET(1)] AS INT64 ) AS p25_cabg_count
FROM cabg_counts;
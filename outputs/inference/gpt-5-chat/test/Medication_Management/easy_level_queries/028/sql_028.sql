WITH antiplatelet_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    LOWER(pr.drug) AS drug_lower,
    pr.starttime,
    pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE LOWER(pr.drug) LIKE '%aspirin%'
    OR LOWER(pr.drug) LIKE '%clopidogrel%'
    OR LOWER(pr.drug) LIKE '%prasugrel%'
    OR LOWER(pr.drug) LIKE '%ticagrelor%'
    OR LOWER(pr.drug) LIKE '%dipyridamole%'
), cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
), dapt_admissions AS (
  SELECT
    ap.subject_id,
    ap.hadm_id
  FROM antiplatelet_prescriptions ap
  JOIN cohort c
    ON ap.subject_id = c.subject_id
   AND ap.hadm_id = c.hadm_id
  GROUP BY ap.subject_id, ap.hadm_id
  HAVING COUNT(DISTINCT ap.drug_lower) >= 2
), single_ap_durations AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    TIMESTAMP_DIFF(ap.stoptime, ap.starttime, HOUR)/24.0 AS duration_days
  FROM antiplatelet_prescriptions ap
  JOIN dapt_admissions da
    ON ap.subject_id = da.subject_id
   AND ap.hadm_id = da.hadm_id
  WHERE ap.starttime IS NOT NULL
    AND ap.stoptime IS NOT NULL
)
SELECT
  STDDEV_POP(duration_days) AS sd_duration_days
FROM single_ap_durations;
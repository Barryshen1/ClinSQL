WITH antiplatelet_drugs AS (
  SELECT 'aspirin' AS drug UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'ticagrelor' UNION ALL
  SELECT 'prasugrel' UNION ALL
  SELECT 'dipyridamole' UNION ALL
  SELECT 'ticlopidine' UNION ALL
  SELECT 'cangrelor'
),
target_patients AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),
antiplatelet_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    LOWER(pr.drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN antiplatelet_drugs ad
    ON LOWER(pr.drug) LIKE CONCAT('%', ad.drug, '%')
  WHERE pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
),
dapt_hadm AS (
  -- For each hadm_id, check if there are at least two antiplatelet drugs with overlapping periods
  SELECT DISTINCT ap1.subject_id, ap1.hadm_id
  FROM antiplatelet_prescriptions ap1
  JOIN antiplatelet_prescriptions ap2
    ON ap1.hadm_id = ap2.hadm_id
    AND ap1.subject_id = ap2.subject_id
    AND ap1.drug <> ap2.drug
    AND ap1.starttime < ap2.stoptime
    AND ap1.stoptime > ap2.starttime
),
single_antiplatelet_periods AS (
  -- For DAPT patients, find single antiplatelet prescription periods (not overlapping with another antiplatelet)
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.drug,
    ap.starttime,
    ap.stoptime,
    TIMESTAMP_DIFF(ap.stoptime, ap.starttime, DAY) AS duration_days
  FROM antiplatelet_prescriptions ap
  JOIN dapt_hadm dapt
    ON ap.subject_id = dapt.subject_id AND ap.hadm_id = dapt.hadm_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM antiplatelet_prescriptions ap2
    WHERE ap2.hadm_id = ap.hadm_id
      AND ap2.subject_id = ap.subject_id
      AND ap2.drug <> ap.drug
      AND ap2.starttime < ap.stoptime
      AND ap2.stoptime > ap.starttime
  )
),
final AS (
  SELECT duration_days
  FROM single_antiplatelet_periods
  WHERE duration_days > 0
)
SELECT
  STDDEV(duration_days) AS sd_single_antiplatelet_duration_days
FROM final
;
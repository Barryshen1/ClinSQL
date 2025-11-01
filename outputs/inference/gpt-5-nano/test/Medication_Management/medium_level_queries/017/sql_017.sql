WITH cohort AS (
  -- basic patient-stay cohort: female, age 37-47, stay >= 144h
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 144
),
cohort_with_diags AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort AS c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON di.icd_code = d.icd_code
     AND di.icd_version = d.icd_version
    WHERE d.subject_id = c.subject_id
      AND d.hadm_id = c.hadm_id
      AND LOWER(di.long_title) LIKE '%diabetes%'
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON di.icd_code = d.icd_code
     AND di.icd_version = d.icd_version
    WHERE d.subject_id = c.subject_id
      AND d.hadm_id = c.hadm_id
      AND LOWER(di.long_title) LIKE '%heart failure%'
  )
),
med_flags AS (
  -- For every admission, evaluate each class (antidiabetics, beta_blockers, acei_arb_arnI, loop_diuretic)
  -- and determine exposure in first 72h and final 72h windows
  SELECT
    cw.subject_id,
    cw.hadm_id,
    class_label,
    MAX(
      CASE
        WHEN pr.starttime IS NOT NULL
             AND pr.starttime <= TIMESTAMP_ADD(cw.admittime, INTERVAL 72 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime >= cw.admittime)
             THEN 1 ELSE 0 END
    ) AS on_first,
    MAX(
      CASE
        WHEN pr.starttime IS NOT NULL
             AND pr.starttime <= cw.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime >= TIMESTAMP_SUB(cw.dischtime, INTERVAL 72 HOUR))
             THEN 1 ELSE 0 END
    ) AS on_final
  FROM cohort_with_diags AS cw
  CROSS JOIN UNNEST(['antidiabetics','beta_blockers','acei_arb_arnI','loop_diuretic']) AS class_label
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = cw.subject_id
   AND pr.hadm_id = cw.hadm_id
   AND (
      -- antidiabetics
      (class_label = 'antidiabetics' AND (
         LOWER(pr.drug) LIKE '%insulin%'
         OR LOWER(pr.drug) LIKE '%metformin%'
         OR LOWER(pr.drug) LIKE '%glipizide%'
         OR LOWER(pr.drug) LIKE '%glyburide%'
         OR LOWER(pr.drug) LIKE '%glimepiride%'
      ))
      OR
      -- beta_blockers
      (class_label = 'beta_blockers' AND (
         LOWER(pr.drug) LIKE '%metoprolol%'
         OR LOWER(pr.drug) LIKE '%atenolol%'
         OR LOWER(pr.drug) LIKE '%carvedilol%'
         OR LOWER(pr.drug) LIKE '%propranolol%'
         OR LOWER(pr.drug) LIKE '%bisoprolol%'
         OR LOWER(pr.drug) LIKE '%labetalol%'
      ))
      OR
      -- acei_arb_arnI
      (class_label = 'acei_arb_arnI' AND (
         LOWER(pr.drug) LIKE '%lisinopril%'
         OR LOWER(pr.drug) LIKE '%enalapril%'
         OR LOWER(pr.drug) LIKE '%ramipril%'
         OR LOWER(pr.drug) LIKE '%captopril%'
         OR LOWER(pr.drug) LIKE '%losartan%'
         OR LOWER(pr.drug) LIKE '%valsartan%'
         OR LOWER(pr.drug) LIKE '%sacubitril%'
      ))
      OR
      -- loop_diuretic
      (class_label = 'loop_diuretic' AND (
         LOWER(pr.drug) LIKE '%furosemide%'
         OR LOWER(pr.drug) LIKE '%torsemide%'
         OR LOWER(pr.drug) LIKE '%bumetanide%'
      ))
    )
  GROUP BY cw.subject_id, cw.hadm_id, class_label
)

SELECT
  class_label,
  COUNT(*) AS total_admissions,
  SUM(on_first) AS first_window_on_count,
  SUM(on_final) AS final_window_on_count,
  SAFE_DIVIDE(SUM(on_first), COUNT(*)) * 100 AS first_window_on_pct,
  SAFE_DIVIDE(SUM(on_final), COUNT(*)) * 100 AS final_window_on_pct,
  SUM(CASE WHEN on_first = 1 AND on_final = 1 THEN 1 ELSE 0 END) AS continued_count,
  SUM(CASE WHEN on_first = 0 AND on_final = 1 THEN 1 ELSE 0 END) AS initiated_count,
  SUM(CASE WHEN on_first = 1 AND on_final = 0 THEN 1 ELSE 0 END) AS discontinued_count
FROM med_flags
GROUP BY class_label
ORDER BY class_label;
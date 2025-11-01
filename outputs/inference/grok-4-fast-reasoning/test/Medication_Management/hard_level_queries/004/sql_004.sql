WITH stroke_patients AS (
  -- Identify all acute ischemic stroke admissions
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
      OR (
        d.icd_version = 9
        AND d.icd_code IN (
          '43301', '43311', '43321', '43331', '43391',
          '43401', '43411', '43491',
          '436'
        )
      )
    )
),
complex_stroke AS (
  -- Add complexity score from APR-DRG severity (proxy for complexity)
  SELECT
    s.*,
    GREATEST(
      COALESCE(MAX(CASE WHEN g.drg_type LIKE '%APR%' THEN CAST(g.drg_severity AS INT64) END), 0),
      0
    ) AS complexity_score
  FROM stroke_patients s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` g
    ON s.subject_id = g.subject_id AND s.hadm_id = g.hadm_id
  GROUP BY
    s.subject_id, s.hadm_id, s.gender, s.anchor_age,
    s.admittime, s.dischtime, s.hospital_expire_flag, s.los_days
),
nti_drugs AS (
  -- Example NTI drugs that are CYP3A4 substrates (common in stroke: statins)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE ANY(
    '%atorvastatin%', '%simvastatin%', '%lovastatin%',
    '%cyclosporine%', '%tacrolimus%'
  )
),
interactors AS (
  -- Example CYP3A4 inhibitors (common hospital drugs)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE ANY(
    '%clarithromycin%', '%erythromycin%', '%telithromycin%',
    '%itraconazole%', '%ketoconazole%', '%voriconazole%', '%posaconazole%',
    '%nefazodone%', '%amiodarone%', '%cimetidine%'
  )
),
has_interaction AS (
  -- Patients with both (potential interaction)
  SELECT n.subject_id, n.hadm_id
  FROM nti_drugs n
  INNER JOIN interactors i
    ON n.subject_id = i.subject_id AND n.hadm_id = i.hadm_id
),
age_cohort AS (
  -- Age/gender filtered cohort with metrics and percentile (rank within cohort)
  SELECT
    *,
    CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END AS mortality,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS complexity_percentile
  FROM complex_stroke
  WHERE gender = 'F' AND anchor_age BETWEEN 48 AND 58
),
comparison AS (
  -- Compare groups by interaction flag
  SELECT
    CASE WHEN has_int = 1 THEN 'With CYP3A4 Interaction' ELSE 'No CYP3A4 Interaction' END AS cohort,
    ROUND(AVG(complexity_score), 2) AS avg_complexity_score,
    ROUND(AVG(complexity_percentile), 4) AS avg_percentile,
    ROUND(AVG(los_days), 2) AS avg_los,
    ROUND(AVG(mortality), 4) AS mortality_rate,
    COUNT(*) AS n_patients
  FROM (
    SELECT
      *,
      CASE
        WHEN EXISTS (
          SELECT 1 FROM has_interaction h
          WHERE age_cohort.subject_id = h.subject_id
            AND age_cohort.hadm_id = h.hadm_id
        ) THEN 1 ELSE 0
      END AS has_int
    FROM age_cohort
  )
  GROUP BY has_int
),
top_quartile_stroke AS (
  -- Top quartile of complexity for all stroke patients
  SELECT
    ROUND(AVG(los_days), 2) AS avg_los,
    ROUND(AVG(mortality), 4) AS mortality_rate,
    COUNT(*) AS n_patients
  FROM (
    SELECT
      los_days,
      CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END AS mortality,
      PERCENT_RANK() OVER (ORDER BY complexity_score DESC) AS pr
    FROM complex_stroke
  ) ranked
  WHERE pr <= 0.25
)
-- Combine results: comparison + top quartile row
SELECT * FROM comparison
UNION ALL
SELECT
  'Top Quartile (All Stroke Patients)' AS cohort,
  NULL AS avg_complexity_score,
  NULL AS avg_percentile,
  avg_los,
  mortality_rate,
  n_patients
FROM top_quartile_stroke
ORDER BY cohort;
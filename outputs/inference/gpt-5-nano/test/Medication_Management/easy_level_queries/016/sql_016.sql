WITH nitrate_cohort AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    CAST(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) AS FLOAT64) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  WHERE
    a.dischtime IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- Age at admission approximation
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
    -- Nitrate-containing drugs
    AND REGEXP_CONTAINS(LOWER(pr.drug), r'(nitro|nitrate|nitroglycerin|isosorbide)')
    -- IV or oral routes
    AND REGEXP_CONTAINS(LOWER(pr.route), r'^(iv|intravenous|iv infusion|intravenous infusion|ivdrip|po|oral|per os)$')
    -- Valid timing
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS p25_duration_days
FROM nitrate_cohort
LIMIT 1;
WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag AS mortality,
    CASE
      WHEN d.icd_code IN ('I630', 'I631', 'I632', 'I633', 'I634', 'I635', 'I636', 'I638', 'I639') AND d.icd_version = 10 THEN 1
      ELSE 0
    END AS is_stroke,
    pr.drug AS prescribed_drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- Identify patients with NTI drugs and CYP3A4 inhibitors
nti_cyp3a4_patients AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    cohort
  WHERE
    LOWER(prescribed_drug) IN (
      'warfarin', 'digoxin', 'phenytoin', 'tacrolimus', 'cyclosporine', -- NTI drugs
      'amiodarone', 'theophylline', 'lithium'
    )
    AND EXISTS (
      SELECT 1
      FROM cohort c2
      WHERE c2.hadm_id = cohort.hadm_id
        AND LOWER(c2.prescribed_drug) IN (
          'clarithromycin', 'itraconazole', 'ketoconazole', 'ritonavir', 'erythromycin'
        )
    )
),

-- Aggregate stats for both groups
group_stats AS (
  SELECT
    CASE
      WHEN ncp.hadm_id IS NOT NULL THEN 'CYP3A4-NTI'
      ELSE 'Age-matched cohort'
    END AS group_name,
    COUNT(*) AS patient_count,
    AVG(los_days) AS avg_los,
    AVG(mortality) AS mortality_rate,
    STDDEV(los_days) AS stddev_los,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los
  FROM
    cohort c
  LEFT JOIN
    nti_cyp3a4_patients ncp
    ON c.hadm_id = ncp.hadm_id
  GROUP BY
    group_name
),

-- Stroke patients in top quartile of LOS
stroke_top_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days DESC) AS los_quartile
  FROM
    cohort
  WHERE
    is_stroke = 1
),

stroke_quartile_stats AS (
  SELECT
    AVG(los_days) AS stroke_top_quartile_los,
    AVG(mortality) AS stroke_top_quartile_mortality
  FROM
    stroke_top_quartile
  WHERE
    los_quartile = 1
)

SELECT
  gs.group_name,
  gs.patient_count,
  gs.avg_los,
  gs.stddev_los,
  gs.median_los,
  gs.mortality_rate,
  gs.avg_los / (gs.stddev_los + 1e-6) AS complexity_score,
  1 - CUME_DIST() OVER (ORDER BY gs.avg_los) AS percentile,
  sqs.stroke_top_quartile_los,
  sqs.stroke_top_quartile_mortality
FROM
  group_stats gs
CROSS JOIN
  stroke_quartile_stats sqs
ORDER BY
  gs.group_name;
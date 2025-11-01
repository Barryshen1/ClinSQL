WITH cardiac_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('I460', 'I461', 'I469') -- Cardiac arrest codes
),

filtered_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 78 AND 88
),

eligible_admissions AS (
  SELECT
    ca.*
  FROM
    cardiac_admissions ca
  JOIN
    filtered_patients fp
    ON ca.subject_id = fp.subject_id
),

med_complexity AS (
  SELECT
    ea.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs,
    COUNT(DISTINCT CASE WHEN p.drug IN (
      'Heparin', 'Warfarin', 'Insulin', 'Furosemide', 'Digoxin'
    ) THEN p.drug END) AS high_risk_drugs,
    COUNT(DISTINCT p.route) AS distinct_routes
  FROM
    eligible_admissions ea
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON ea.hadm_id = p.hadm_id
  WHERE
    p.starttime >= ea.admittime
    AND p.starttime <= DATETIME_ADD(ea.admittime, INTERVAL 7 DAY)
  GROUP BY
    ea.hadm_id
),

scored_admissions AS (
  SELECT
    ea.*,
    COALESCE(mc.unique_drugs, 0) AS unique_drugs,
    COALESCE(mc.high_risk_drugs, 0) AS high_risk_drugs,
    COALESCE(mc.distinct_routes, 0) AS distinct_routes,
    COALESCE(mc.unique_drugs, 0) + 2 * COALESCE(mc.high_risk_drugs, 0) + COALESCE(mc.distinct_routes, 0) AS complexity_score
  FROM
    eligible_admissions ea
  LEFT JOIN
    med_complexity mc
    ON ea.hadm_id = mc.hadm_id
),

tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS score_tertile
  FROM
    scored_admissions
),

readmissions AS (
  SELECT
    t1.subject_id,
    t1.hadm_id AS index_hadm_id,
    t1.dischtime AS index_dischtime,
    t1.hospital_expire_flag,
    t1.los,
    t1.complexity_score,
    t1.score_tertile,
    MIN(t2.admittime) AS next_admittime
  FROM
    tertiles t1
  LEFT JOIN
    tertiles t2
    ON t1.subject_id = t2.subject_id
    AND t2.admittime > t1.dischtime
    AND DATETIME_DIFF(t2.admittime, t1.dischtime, DAY) <= 30
    AND t1.hospital_expire_flag = 0
  GROUP BY
    t1.subject_id, t1.hadm_id, t1.dischtime, t1.hospital_expire_flag, t1.los, t1.complexity_score, t1.score_tertile
),

final_stats AS (
  SELECT
    score_tertile,
    COUNT(*) AS admission_count,
    MIN(complexity_score) AS min_score,
    MAX(complexity_score) AS max_score,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hosp_mortality_pct,
    AVG(
      CASE
        WHEN hospital_expire_flag = 0 AND next_admittime IS NOT NULL THEN 1.0
        ELSE 0.0
      END
    ) * 100 AS readmission_30d_pct
  FROM
    readmissions
  GROUP BY
    score_tertile
)

SELECT
  score_tertile,
  admission_count,
  min_score,
  max_score,
  ROUND(mean_los, 2) AS mean_los,
  ROUND(in_hosp_mortality_pct, 2) AS in_hosp_mortality_pct,
  ROUND(readmission_30d_pct, 2) AS readmission_30d_pct
FROM
  final_stats
ORDER BY
  score_tertile;
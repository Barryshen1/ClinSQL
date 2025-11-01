WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    MIN(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    -- crude lower GI bleed filter; in production, use exact list of ICD codes
    AND (
      LOWER(dd.long_title) LIKE '%lower%gastro%bleed%'
      OR LOWER(dd.long_title) LIKE '%lower%gi%bleed%'
      OR LOWER(dd.long_title) LIKE '%rectal%bleed%'
      OR LOWER(dd.long_title) LIKE '%hematochezia%'
    )
  GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, p.dod
),
complications AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    SUM(
      CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%' THEN 1 ELSE 0 END
      + CASE WHEN LOWER(dd.long_title) LIKE '%acute%kidney%fail%' THEN 1 ELSE 0 END
      + CASE WHEN LOWER(dd.long_title) LIKE '%respiratory%failure%' THEN 1 ELSE 0 END
      + CASE WHEN LOWER(dd.long_title) LIKE '%shock%' THEN 1 ELSE 0 END
      + CASE WHEN LOWER(dd.long_title) LIKE '%myocardial%infarction%' THEN 1 ELSE 0 END
    ) AS risk_score,
    MAX(
      CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%'
                OR LOWER(dd.long_title) LIKE '%acute%kidney%fail%'
                OR LOWER(dd.long_title) LIKE '%respiratory%failure%'
                OR LOWER(dd.long_title) LIKE '%shock%'
                OR LOWER(dd.long_title) LIKE '%myocardial%infarction%' THEN 1 ELSE 0 END
    ) AS has_complication
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY c.subject_id, c.hadm_id
),
scored AS (
  SELECT
    c.*,
    comp.risk_score,
    comp.has_complication,
    NTILE(5) OVER (ORDER BY comp.risk_score) AS risk_quintile
  FROM cohort c
  JOIN complications comp
    ON c.subject_id = comp.subject_id AND c.hadm_id = comp.hadm_id
),
outcomes AS (
  SELECT
    risk_quintile,
    COUNT(*) AS N,
    AVG(CASE WHEN dod IS NOT NULL
               AND TIMESTAMP_DIFF(dod, admittime, DAY) <= 90
             THEN 1 ELSE 0 END) AS mortality_90d_rate,
    AVG(CASE WHEN has_complication = 1 THEN 1 ELSE 0 END) AS major_complication_rate,
    -- Median LOS among 90-day survivors
    APPROX_QUANTILES(CASE WHEN dod IS NULL
                                OR TIMESTAMP_DIFF(dod, admittime, DAY) > 90
                           THEN los_days END, 100)[OFFSET(50)] AS median_los_90d_survivors
  FROM scored
  GROUP BY risk_quintile
)
SELECT
  risk_quintile,
  N,
  mortality_90d_rate,
  major_complication_rate,
  median_los_90d_survivors
FROM outcomes
ORDER BY risk_quintile;
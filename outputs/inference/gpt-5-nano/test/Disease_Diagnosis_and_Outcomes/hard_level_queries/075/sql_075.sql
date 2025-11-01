WITH
  -- Base: female, age 44-54
  base AS (
    SELECT
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.subject_id,
      p.dod AS dod,
      p.gender,
      p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 44 AND 54
  ),

  -- ICH flag per admission
  ich_flags AS (
    SELECT
      b.hadm_id,
      MAX(CASE
            WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                 r'intracranial hemorrhage|intracerebral hemorrhage|subarachnoid hemorrhage')
            THEN 1 ELSE 0 END) AS has_ich
    FROM base b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON di.hadm_id = b.hadm_id
     AND di.subject_id = b.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    GROUP BY b.hadm_id
  ),

  -- Charlson-like comorbidity flags (simple binary indicators)
  charlson_flags AS (
    SELECT
      b.hadm_id,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'myocardial infarction') THEN 1 ELSE 0 END) AS has_MI,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'congestive heart failure|heart failure') THEN 1 ELSE 0 END) AS has_CHF,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'cerebrovascular|stroke') THEN 1 ELSE 0 END) AS has_cerebrovascular,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'dementia') THEN 1 ELSE 0 END) AS has_dementia,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'chronic obstructive pulmonary disease|copd') THEN 1 ELSE 0 END) AS has_COPD,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'diabetes mellitus') THEN 1 ELSE 0 END) AS has_diabetes,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'peptic ulcer') THEN 1 ELSE 0 END) AS has_PUD,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'liver') THEN 1 ELSE 0 END) AS has_liver,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'kidney|renal') THEN 1 ELSE 0 END) AS has_renal,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'malignant neoplasm|cancer') THEN 1 ELSE 0 END) AS has_malignancy,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'metastatic') THEN 1 ELSE 0 END) AS has_metastasis,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                    r'aids|acquired immunodeficiency syndrome') THEN 1 ELSE 0 END) AS has_AIDS
    FROM base b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON di.hadm_id = b.hadm_id
     AND di.subject_id = b.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    GROUP BY b.hadm_id
  ),

  -- Major complications (fixed high-impact diagnoses)
  major_comp AS (
    SELECT
      b.hadm_id,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'sepsis') THEN 1 ELSE 0 END) AS has_sepsis,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'pneumonia') THEN 1 ELSE 0 END) AS has_pneumonia,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'(acute kidney|kidney) failure') THEN 1 ELSE 0 END) AS has_kidney_failure,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'(acute|respiratory) failure|ARDS') THEN 1 ELSE 0 END) AS has_ARDS,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'myocardial infarction') THEN 1 ELSE 0 END) AS has_MI2,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'stroke') THEN 1 ELSE 0 END) AS has_stroke,
      MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title),
                                   r'pulmonary embolism') THEN 1 ELSE 0 END) AS has_PE
    FROM base b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON di.hadm_id = b.hadm_id
     AND di.subject_id = b.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    GROUP BY b.hadm_id
  ),

  -- Death within 90 days and LOS calculations
  death_los AS (
    SELECT
      b.hadm_id,
      CASE WHEN dod IS NOT NULL AND dod <= TIMESTAMP_ADD(admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS death_90d,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM base b
  ),

  -- Assemble per-admission final features
  final AS (
    SELECT
      b.hadm_id,
      b.subject_id,
      b.admittime,
      b.dischtime,
      b.dod,
      IFNULL(ic.has_ich, 0) AS has_ich,
      IFNULL(ch.has_MI, 0) AS has_MI,
      IFNULL(ch.has_CHF, 0) AS has_CHF,
      IFNULL(ch.has_cerebrovascular, 0) AS has_cerebrovascular,
      IFNULL(ch.has_dementia, 0) AS has_dementia,
      IFNULL(ch.has_COPD, 0) AS has_COPD,
      IFNULL(ch.has_diabetes, 0) AS has_diabetes,
      IFNULL(ch.has_PUD, 0) AS has_PUD,
      IFNULL(ch.has_liver, 0) AS has_liver,
      IFNULL(ch.has_renal, 0) AS has_renal,
      IFNULL(ch.has_malignancy, 0) AS has_malignancy,
      IFNULL(ch.has_metastasis, 0) AS has_metastasis,
      IFNULL(ch.has_AIDS, 0) AS has_AIDS,
      /* Charlson-like risk score: sum of present comorbidity flags */
      (IFNULL(ch.has_MI,0) + IFNULL(ch.has_CHF,0) + IFNULL(ch.has_cerebrovascular,0) +
       IFNULL(ch.has_dementia,0) + IFNULL(ch.has_COPD,0) + IFNULL(ch.has_diabetes,0) +
       IFNULL(ch.has_PUD,0) + IFNULL(ch.has_liver,0) + IFNULL(ch.has_renal,0) +
       IFNULL(ch.has_malignancy,0) + IFNULL(ch.has_metastasis,0) + IFNULL(ch.has_AIDS,0)) AS risk_score,
      dl.death_90d,
      dl.los_days,
      CASE WHEN (dod IS NULL OR dod > TIMESTAMP_ADD(admittime, INTERVAL 90 DAY)) THEN 1 ELSE 0 END AS is_survivor,
      CASE WHEN (mc.has_sepsis + mc.has_pneumonia + mc.has_kidney_failure +
                 mc.has_ARDS + mc.has_MI2 + mc.has_stroke + mc.has_PE) > 0 THEN 1 ELSE 0 END AS major_complication
    FROM base b
    LEFT JOIN ich_flags ic ON ic.hadm_id = b.hadm_id
    LEFT JOIN charlson_flags ch ON ch.hadm_id = b.hadm_id
    LEFT JOIN major_comp mc ON mc.hadm_id = b.hadm_id
    LEFT JOIN death_los dl ON dl.hadm_id = b.hadm_id
  )

SELECT
  -- ICH group metrics
  MEDIAN(risk_score) FILTER (WHERE has_ich = 1) AS ich_median_risk,
  (SELECT (APPROX_QUANTILES(risk_score, 4))[OFFSET(1)] FROM final f WHERE f.has_ich = 1) AS ich_risk_q1,
  (SELECT (APPROX_QUANTILES(risk_score, 4))[OFFSET(3)] FROM final f WHERE f.has_ich = 1) AS ich_risk_q3,
  AVG(death_90d) FILTER (WHERE has_ich = 1) AS ich_90d_mort,
  AVG(major_complication) FILTER (WHERE has_ich = 1) AS ich_major_comp_rate,
  MEDIAN(los_days) FILTER (WHERE has_ich = 1 AND is_survivor = 1) AS ich_median_survivor_los,

  -- New percentile calculation for matched risk
  (SELECT MEDIAN(percentile) FROM (
     SELECT 100.0 * (SELECT COUNT(*) FROM final f2
                       WHERE f2.is_survivor = 1 AND f2.has_ich = 0 AND f2.risk_score <= f1.risk_score) /
                    (SELECT COUNT(*) FROM final f3
                       WHERE f3.is_survivor = 1 AND f3.has_ich = 0) AS percentile
     FROM final f1
     WHERE f1.has_ich = 1 AND f1.is_survivor = 1
  ) AS t) AS ich_risk_percentile,

  -- Comparator (non-ICH) group metrics
  MEDIAN(risk_score) FILTER (WHERE has_ich = 0) AS comp_median_risk,
  (SELECT (APPROX_QUANTILES(risk_score, 4))[OFFSET(1)] FROM final f WHERE f.has_ich = 0) AS comp_risk_q1,
  (SELECT (APPROX_QUANTILES(risk_score, 4))[OFFSET(3)] FROM final f WHERE f.has_ich = 0) AS comp_risk_q3,
  AVG(death_90d) FILTER (WHERE has_ich = 0) AS comp_90d_mort,
  AVG(major_complication) FILTER (WHERE has_ich = 0) AS comp_major_comp_rate,
  MEDIAN(los_days) FILTER (WHERE has_ich = 0 AND is_survivor = 1) AS comp_median_survivor_los
FROM final;
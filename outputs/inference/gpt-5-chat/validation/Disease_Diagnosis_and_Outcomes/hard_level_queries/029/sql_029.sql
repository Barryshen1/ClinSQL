WITH pneumonia_cohort AS (
  SELECT DISTINCT adm.subject_id,
         adm.hadm_id,
         pat.gender,
         pat.anchor_age,
         adm.admittime,
         adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (
      -- pneumonia ICD9 codes
      (dx.icd_version = 9 AND REGEXP_CONTAINS(dx.icd_code, r'^(48[0-6]|487|488)'))
      -- pneumonia ICD10 codes
      OR (dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^(J1[2-8])'))
    )
),
risk_scores AS (
  SELECT pc.*,
         -- placeholder risk score: age + LOS in days
         SAFE_DIVIDE(TIMESTAMP_DIFF(pc.dischtime, pc.admittime, HOUR), 24) AS los_days,
         (pc.anchor_age +
          SAFE_DIVIDE(TIMESTAMP_DIFF(pc.dischtime, pc.admittime, HOUR), 24)
         ) AS risk_score
  FROM pneumonia_cohort pc
),
complications_flags AS (
  SELECT DISTINCT rs.hadm_id,
    MAX(CASE
        WHEN dx.icd_version = 9 AND REGEXP_CONTAINS(dx.icd_code, r'^(410|411|412|413|414|428|427)') THEN 1
        WHEN dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^(I2[0-5]|I6[0-9]|I7[0-5])') THEN 1
        ELSE 0 END) AS cv_complication,
    MAX(CASE
        WHEN dx.icd_version = 9 AND REGEXP_CONTAINS(dx.icd_code, r'^(430|431|432|433|434|435|436|437|438|780\.39)') THEN 1
        WHEN dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^(G4[0-6]|G81|I6[0-9])') THEN 1
        ELSE 0 END) AS neuro_complication
  FROM risk_scores rs
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON rs.subject_id = dx.subject_id AND rs.hadm_id = dx.hadm_id
  GROUP BY rs.hadm_id
),
mortality_flag AS (
  SELECT rs.hadm_id,
         CASE
           WHEN pat.dod IS NOT NULL
            AND TIMESTAMP_DIFF(pat.dod, rs.admittime, DAY) <= 30 THEN 1
           ELSE 0
         END AS mortality_30d
  FROM risk_scores rs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON rs.subject_id = pat.subject_id
),
quintiles AS (
  SELECT rs.*,
         cf.cv_complication,
         cf.neuro_complication,
         mf.mortality_30d,
         NTILE(5) OVER (ORDER BY rs.risk_score) AS risk_quintile
  FROM risk_scores rs
  LEFT JOIN complications_flags cf
    ON rs.hadm_id = cf.hadm_id
  LEFT JOIN mortality_flag mf
    ON rs.hadm_id = mf.hadm_id
)
SELECT risk_quintile,
       COUNT(*) AS total_admissions,
       ROUND(100 * SUM(mortality_30d) / COUNT(*), 2) AS mortality_30d_pct,
       ROUND(100 * SUM(cv_complication) / COUNT(*), 2) AS cv_complication_pct,
       ROUND(100 * SUM(neuro_complication) / COUNT(*), 2) AS neuro_complication_pct,
       APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_survivors
FROM quintiles
WHERE mortality_30d = 0 -- survivors only for median LOS
GROUP BY risk_quintile
ORDER BY risk_quintile;
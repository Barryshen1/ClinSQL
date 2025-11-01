WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
),
ugi_bleed AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE (
      -- ICD-9
      (di.icd_version = 9 AND (
        di.icd_code LIKE '578%'
        OR di.icd_code LIKE '531%' OR di.icd_code LIKE '532%' 
        OR di.icd_code LIKE '533%' OR di.icd_code LIKE '534%'
        OR di.icd_code LIKE '535%'
      ))
      -- ICD-10
      OR (di.icd_version = 10 AND (
        di.icd_code LIKE 'K92%' 
        OR di.icd_code LIKE 'K25%' OR di.icd_code LIKE 'K26%'
        OR di.icd_code LIKE 'K27%' OR di.icd_code LIKE 'K28%'
      ))
    )
),
diagnosis_counts AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS dx_count,
    MAX(CASE 
      -- major complication flag: sepsis, acute renal failure, shock
      WHEN (
        (di.icd_version = 9 AND (
          di.icd_code LIKE '99591' OR di.icd_code LIKE '99592'
          OR di.icd_code LIKE '78552'
          OR di.icd_code LIKE '584%'
          OR di.icd_code LIKE '7855%'
        ))
        OR (di.icd_version = 10 AND (
          di.icd_code LIKE 'A41%' 
          OR di.icd_code LIKE 'N17%'
          OR di.icd_code LIKE 'R57%'
        ))
      ) THEN 1 ELSE 0 END) AS major_complication_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
scored AS (
  SELECT
    c.*,
    dc.dx_count,
    dc.major_complication_flag,
    dc.dx_count + 20 * dc.major_complication_flag AS risk_score
  FROM cohort c
  JOIN ugi_bleed u
    ON c.subject_id = u.subject_id AND c.hadm_id = u.hadm_id
  LEFT JOIN diagnosis_counts dc
    ON c.subject_id = dc.subject_id AND c.hadm_id = dc.hadm_id
),
with_quintile AS (
  SELECT
    s.*,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile,
    CASE 
      WHEN s.dod IS NOT NULL AND DATETIME_DIFF(s.dod, s.admittime, DAY) <= 30 THEN 1
      WHEN s.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mort30d
  FROM scored s
)
SELECT
  risk_quintile,
  COUNT(*) AS n,
  ROUND(AVG(risk_score),2) AS mean_score,
  ROUND(100*AVG(mort30d),1) AS mort30d_pct,
  ROUND(100*AVG(major_complication_flag),1) AS major_complication_pct,
  ROUND(APPROX_QUANTILES(
    CASE WHEN mort30d = 0 THEN DATETIME_DIFF(dischtime, admittime, DAY) END, 2
  )[OFFSET(1)],1) AS median_los_survivors
FROM with_quintile
GROUP BY risk_quintile
ORDER BY risk_quintile;
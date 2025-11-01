WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
      WHERE 
        diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND REGEXP_CONTAINS(d.long_title, r'(?i)cardiac arrest')
    )
),
filtered_cohort AS (
  SELECT 
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM cohort
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 78 AND 88
),
medication_complexity AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs,
    COUNT(DISTINCT 
      CASE 
        WHEN REGEXP_CONTAINS(pr.drug, r'(?i)insulin|warfarin|heparin|morphine|fentanyl|diltiazem|digoxin|epinephrine')
        THEN pr.drug 
      END
    ) AS high_risk_drugs,
    COUNT(DISTINCT pr.route) AS distinct_routes
  FROM filtered_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),
readmission_flags AS (
  SELECT 
    c.hadm_id,
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN NULL
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE 
          a2.subject_id = c.subject_id
          AND a2.hadm_id <> c.hadm_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0 
    END AS readmit_30d
  FROM filtered_cohort c
),
combined_data AS (
  SELECT 
    c.*,
    COALESCE(m.unique_drugs, 0) AS unique_drugs,
    COALESCE(m.high_risk_drugs, 0) AS high_risk_drugs,
    COALESCE(m.distinct_routes, 0) AS distinct_routes,
    COALESCE(m.unique_drugs, 0) + 2 * COALESCE(m.high_risk_drugs, 0) + COALESCE(m.distinct_routes, 0) AS complexity_score,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    r.readmit_30d
  FROM filtered_cohort c
  LEFT JOIN medication_complexity m ON c.hadm_id = m.hadm_id
  LEFT JOIN readmission_flags r ON c.hadm_id = r.hadm_id
),
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM combined_data
)
SELECT 
  tertile,
  COUNT(*) AS count_admissions,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(readmit_30d) * 100 AS readmission_30d_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;
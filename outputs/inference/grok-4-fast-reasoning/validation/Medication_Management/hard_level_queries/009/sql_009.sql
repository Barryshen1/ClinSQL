WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
          OR
          (di.icd_version = 9 AND di.icd_code LIKE '584%')
        )
    )
),
med_scores AS (
  SELECT 
    c.*,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.drug IS NOT NULL
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.age_at_admit
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score ASC) AS quintile
  FROM med_scores
),
flags AS (
  SELECT 
    q.*,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = q.subject_id
        AND a2.hadm_id != q.hadm_id
        AND a2.admittime > q.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(q.dischtime, INTERVAL 30 DAY)
    ) AS has_readmit,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.hadm_id = q.hadm_id
        AND (
          UPPER(pr.drug) LIKE '%HEPARIN%' OR
          UPPER(pr.drug) LIKE '%ENOXAPARIN%' OR
          UPPER(pr.drug) LIKE '%WARFARIN%' OR
          UPPER(pr.drug) LIKE '%RIVAROXABAN%' OR
          UPPER(pr.drug) LIKE '%APIXABAN%' OR
          UPPER(pr.drug) LIKE '%DABIGATRAN%' OR
          UPPER(pr.drug) LIKE '%FONDAPARINUX%' OR
          UPPER(pr.drug) LIKE '%ARGATROBAN%' OR
          UPPER(pr.drug) LIKE '%BIVALIRUDIN%'
        )
    ) AS has_anticoag,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.hadm_id = q.hadm_id
        AND (
          UPPER(pr.drug) LIKE '%MORPHINE%' OR
          UPPER(pr.drug) LIKE '%FENTANYL%' OR
          UPPER(pr.drug) LIKE '%HYDROMORPHONE%' OR
          UPPER(pr.drug) LIKE '%OXYCODONE%' OR
          UPPER(pr.drug) LIKE '%HYDROCODONE%' OR
          UPPER(pr.drug) LIKE '%CODEINE%' OR
          UPPER(pr.drug) LIKE '%TRAMADOL%' OR
          UPPER(pr.drug) LIKE '%METHADONE%' OR
          UPPER(pr.drug) LIKE '%BUPRENORPHINE%' OR
          UPPER(pr.drug) LIKE '%MEPERIDINE%' OR
          UPPER(pr.drug) LIKE '%OXYMORPHONE%'
        )
    ) AS has_opioid
  FROM quintiles q
)
SELECT 
  quintile,
  COUNT(*) AS n_admissions,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  (SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*)) AS inpatient_mortality_pct,
  SAFE_DIVIDE(
    SUM(CASE WHEN hospital_expire_flag = 0 AND has_readmit THEN 1 ELSE 0 END) * 100.0,
    SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)
  ) AS readmission_30d_pct,
  SUM(CASE WHEN has_anticoag AND has_opioid THEN 1 ELSE 0 END) AS coadmin_count
FROM flags
GROUP BY quintile
ORDER BY quintile;
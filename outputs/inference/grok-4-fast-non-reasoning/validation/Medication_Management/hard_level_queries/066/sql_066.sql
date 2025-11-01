WITH cohort AS (
  -- Base cohort: males aged 43-53 with transplant diagnosis
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND (d.icd_code LIKE 'Z94%' OR d.icd_code LIKE 'V42%')
  QUALIFY rn = 1  -- First matching admission per patient
),

los_readmit AS (
  -- Add LOS and 30-day readmission flag
  SELECT 
    c.*,
    DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) AS los,
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN 0
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= DATE_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmit_30d
  FROM cohort c
),

meds AS (
  -- Medications in first 7 days from prescriptions
  SELECT 
    lr.hadm_id,
    LOWER(TRIM(pres.drug)) AS med_name,
    pres.route,
    pres.doses_per_24_hrs
  FROM los_readmit lr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON lr.hadm_id = pres.hadm_id
  WHERE pres.drug IS NOT NULL
    AND pres.starttime >= lr.admittime
    AND pres.starttime < TIMESTAMP_ADD(lr.admittime, INTERVAL 7 DAY)
),

mcs_scores AS (
  -- Compute MCS per hadm_id
  SELECT 
    lr.hadm_id,
    lr.los,
    lr.hospital_expire_flag,
    lr.readmit_30d,
    COALESCE(
      SUM(
        CASE 
          WHEN um.route IN ('PO', 'oral') AND um.doses_per_24_hrs <= 2 THEN 1
          WHEN um.route IN ('IV', 'intravenous') OR um.doses_per_24_hrs > 2 THEN 2
          ELSE 1  -- Default simple
        END + 
        CASE 
          WHEN LOWER(um.med_name) LIKE ANY (
            '%warfarin%', '%heparin%', '%cyclosporine%', '%tacrolimus%', 
            '%mycophenolate%', '%sirolimus%', '%chemotherapy%', '%prednisone%'
          ) THEN 0.5 
          ELSE 0 
        END
      ), 0
    ) AS mcs_score
  FROM los_readmit lr
  LEFT JOIN (
    SELECT DISTINCT hadm_id, med_name, route, doses_per_24_hrs
    FROM meds
  ) um ON lr.hadm_id = um.hadm_id
  GROUP BY lr.hadm_id, lr.los, lr.hospital_expire_flag, lr.readmit_30d
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY mcs_score) AS quartile
  FROM mcs_scores
)

-- Final aggregates per quartile
SELECT 
  quartile,
  COUNT(*) AS n,
  ROUND(AVG(mcs_score), 2) AS mean_score,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_pct,
  ROUND(AVG(readmit_30d) * 100, 2) AS readmit_rate_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile;
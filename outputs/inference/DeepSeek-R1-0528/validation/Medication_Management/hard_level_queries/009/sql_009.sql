WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    -- Ensure admission is valid (exclude transfers only)
    AND adm.hadm_id IS NOT NULL
    -- AKI diagnosis filter
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '584%') OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
        )
    )
),

filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_adm BETWEEN 84 AND 94
),

med_complexity AS (
  SELECT 
    hadm_id, 
    COUNT(DISTINCT drug) AS med_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM filtered_cohort)
  GROUP BY hadm_id
),

cohort_with_med AS (
  SELECT 
    fc.*,
    COALESCE(mc.med_score, 0) AS med_score
  FROM filtered_cohort fc
  LEFT JOIN med_complexity mc
    ON fc.hadm_id = mc.hadm_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY med_score) AS quintile
  FROM cohort_with_med
),

readmission_flags AS (
  SELECT 
    hadm_id, 
    LEAD(admittime) OVER (
      PARTITION BY subject_id 
      ORDER BY admittime
    ) AS next_admittime
  FROM quintiles
),

cohort_with_readmission AS (
  SELECT 
    q.*,
    rf.next_admittime,
    -- Only survivors can be readmitted
    CASE 
      WHEN q.hospital_expire_flag = 0 
        AND DATE_DIFF(rf.next_admittime, q.dischtime, DAY) BETWEEN 0 AND 30 
      THEN 1 
      ELSE 0 
    END AS readmission_flag
  FROM quintiles q
  LEFT JOIN readmission_flags rf
    ON q.hadm_id = rf.hadm_id
),

anticoagulants AS (
  SELECT 
    hadm_id, 
    DATE(charttime) AS admin_date
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM quintiles)
    AND LOWER(medication) LIKE ANY (
      '%warfarin%', '%heparin%', '%enoxaparin%', '%dalteparin%', 
      '%tinzaparin%', '%fondaparinux%', '%argatroban%', '%bivalirudin%', 
      '%dabigatran%', '%rivaroxaban%', '%apixaban%', '%edoxaban%'
    )
  GROUP BY hadm_id, admin_date
),

opioids AS (
  SELECT 
    hadm_id, 
    DATE(charttime) AS admin_date
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM quintiles)
    AND LOWER(medication) LIKE ANY (
      '%morphine%', '%fentanyl%', '%hydromorphone%', '%oxycodone%', 
      '%oxymorphone%', '%hydrocodone%', '%codeine%', '%tramadol%', 
      '%methadone%', '%buprenorphine%'
    )
  GROUP BY hadm_id, admin_date
),

coadmin_days AS (
  SELECT 
    a.hadm_id, 
    a.admin_date
  FROM anticoagulants a
  INNER JOIN opioids o
    ON a.hadm_id = o.hadm_id 
    AND a.admin_date = o.admin_date
  GROUP BY a.hadm_id, a.admin_date
),

coadmin_per_admission AS (
  SELECT 
    hadm_id, 
    COUNT(admin_date) AS coadmin_count
  FROM coadmin_days
  GROUP BY hadm_id
),

final_cohort AS (
  SELECT 
    cwr.*,
    COALESCE(cpa.coadmin_count, 0) AS coadmin_count
  FROM cohort_with_readmission cwr
  LEFT JOIN coadmin_per_admission cpa
    ON cwr.hadm_id = cpa.hadm_id
)

SELECT 
  quintile,
  COUNT(*) AS admissions,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  -- Readmission %: (readmissions / survivors) * 100
  SAFE_DIVIDE(
    SUM(readmission_flag), 
    SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)
  ) * 100 AS readmission_30d_pct,
  AVG(coadmin_count) AS avg_coadmin_days
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;
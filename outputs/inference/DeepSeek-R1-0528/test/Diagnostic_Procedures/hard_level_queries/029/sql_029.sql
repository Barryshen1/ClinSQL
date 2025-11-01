WITH cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.ingredientevents` v
      INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON v.itemid = di.itemid
      WHERE v.stay_id = i.stay_id
        AND v.starttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
        AND LOWER(di.label) IN (
          'norepinephrine', 'epinephrine', 'vasopressin', 'dopamine', 'phenylephrine'
        )
    )
),
first_icu_stay AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_rank
  FROM cohort
),
labs AS (
  SELECT 
    f.stay_id,
    COUNT(l.labevent_id) AS lab_count
  FROM first_icu_stay f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    AND f.stay_rank = 1
  GROUP BY f.stay_id
),
imaging AS (
  SELECT 
    f.stay_id,
    COUNT(*) AS img_count  -- Fixed: procedure_id column doesn't exist
  FROM first_icu_stay f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE pe.starttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    AND di.category IN ('Radiology', 'Ultrasound', 'CT', 'MRI', 'X-ray', 'Nuclear Medicine', 'Angiography')
    AND f.stay_rank = 1
  GROUP BY f.stay_id
),
diagnostic_load AS (
  SELECT 
    f.stay_id,
    COALESCE(l.lab_count, 0) + COALESCE(i.img_count, 0) AS diag_count
  FROM first_icu_stay f
  LEFT JOIN labs l ON f.stay_id = l.stay_id
  LEFT JOIN imaging i ON f.stay_id = i.stay_id
  WHERE f.stay_rank = 1
),
quartiles AS (
  SELECT 
    stay_id,
    diag_count,
    NTILE(4) OVER (ORDER BY diag_count) AS diag_quartile
  FROM diagnostic_load
),
procedures AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT CONCAT(icd_code, '_', icd_version)) AS proc_count
  FROM (
    SELECT hadm_id, icd_code, icd_version 
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    UNION ALL
    SELECT hadm_id, hcpcs_cd AS icd_code, NULL AS icd_version 
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  )
  GROUP BY hadm_id
),
readmissions AS (
  SELECT 
    a1.hadm_id,
    MAX(CASE 
      WHEN a1.hospital_expire_flag = 1 THEN 0  -- Exclude deceased
      WHEN a2.hadm_id IS NOT NULL THEN 1 
      ELSE 0 
    END) AS readmit_30_flag
  FROM first_icu_stay a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
    AND a1.hadm_id <> a2.hadm_id
  WHERE a1.stay_rank = 1
  GROUP BY a1.hadm_id
)
SELECT 
  q.diag_quartile,
  AVG(p.proc_count) AS avg_procedure_count,
  AVG(DATETIME_DIFF(f.dischtime, f.admittime, DAY)) AS avg_los_days,
  AVG(f.hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(r.readmit_30_flag) AS readmission_30_rate
FROM quartiles q
INNER JOIN first_icu_stay f 
  ON q.stay_id = f.stay_id AND f.stay_rank = 1
LEFT JOIN procedures p 
  ON f.hadm_id = p.hadm_id
LEFT JOIN readmissions r 
  ON f.hadm_id = r.hadm_id
GROUP BY q.diag_quartile
ORDER BY q.diag_quartile;
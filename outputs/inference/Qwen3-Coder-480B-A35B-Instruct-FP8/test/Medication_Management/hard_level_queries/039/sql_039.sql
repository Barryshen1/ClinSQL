WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    a.admission_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),

-- ICH diagnosis filter
ich_admissions AS (
  SELECT DISTINCT c.*
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.icd_version = 10
    AND (
      (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
      AND d.icd_code NOT LIKE 'I60%'
    )
),

-- ICU stays
icu AS (
  SELECT
    stay_id,
    hadm_id,
    intime AS icu_intime,
    outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Medication complexity in first 48 hours of ICU stay
meds_first48 AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT CONCAT(e.medication, '|', ed.route)) AS med_complexity
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
  JOIN icu i
    ON e.hadm_id = i.hadm_id
  WHERE
    e.charttime >= i.icu_intime
    AND e.charttime <= DATETIME_ADD(i.icu_intime, INTERVAL 48 HOUR)
    AND e.medication IS NOT NULL
    AND ed.route IS NOT NULL
  GROUP BY e.hadm_id
),

-- Add complexity score and quartiles
quartiles AS (
  SELECT
    i.*,
    m.med_complexity,
    NTILE(4) OVER (ORDER BY m.med_complexity) AS complexity_quartile
  FROM ich_admissions i
  JOIN meds_first48 m
    ON i.hadm_id = m.hadm_id
),

-- 30-day readmission flag
readmissions AS (
  SELECT
    q.*,
    CASE
      WHEN LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) IS NOT NULL
        AND DATETIME_DIFF(
          LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime),
          q.dischtime,
          DAY
        ) <= 30 THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM quartiles q
)

-- Final aggregation by quartile
SELECT
  complexity_quartile,
  COUNT(*) AS admissions,
  MIN(med_complexity) AS min_score,
  MAX(med_complexity) AS max_score,
  AVG(los) AS avg_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(readmit_30_days) * 100, 2) AS readmit_30d_percent
FROM readmissions
GROUP BY complexity_quartile
ORDER BY complexity_quartile;
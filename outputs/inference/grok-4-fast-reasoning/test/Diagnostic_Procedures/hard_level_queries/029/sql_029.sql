WITH first_stays AS (
  SELECT hadm_id, MIN(stay_id) AS stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    fs.hadm_id, 
    fs.stay_id, 
    i.intime, 
    i.subject_id,
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    a.dischtime, 
    a.hospital_expire_flag,
    a.admittime,
    p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year AS age
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i 
    ON i.stay_id = fs.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 68 AND 78
),
vaso_cohort AS (
  SELECT *
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu`.inputevents ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di 
      ON ie.itemid = di.itemid
    WHERE ie.stay_id = c.stay_id
      AND ie.starttime >= c.intime
      AND ie.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
      AND (LOWER(di.label) LIKE '%norepinephrine%'
           OR LOWER(di.label) LIKE '%epinephrine%'
           OR LOWER(di.label) LIKE '%dopamine%'
           OR LOWER(di.label) LIKE '%phenylephrine%'
           OR LOWER(di.label) LIKE '%vasopressin%')
      AND COALESCE(ie.amount, 0) > 0
  )
),
labs_cte AS (
  SELECT 
    vc.hadm_id,
    COUNT(le.labevent_id) AS num_labs
  FROM vaso_cohort vc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON le.hadm_id = vc.hadm_id
    AND le.charttime >= vc.intime
    AND le.charttime <= TIMESTAMP_ADD(vc.intime, INTERVAL 72 HOUR)
  GROUP BY vc.hadm_id
),
imaging_cte AS (
  SELECT 
    vc.hadm_id,
    COUNT(pi.icd_code) AS num_imaging
  FROM vaso_cohort vc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON pi.hadm_id = vc.hadm_id
    AND (
      (pi.icd_version = 9 AND (pi.icd_code LIKE '87%' OR pi.icd_code LIKE '88%'))
      OR (pi.icd_version = 10 AND pi.icd_code LIKE 'B%')
    )
    AND pi.chartdate >= DATE(vc.intime)
    AND pi.chartdate <= DATE(TIMESTAMP_ADD(vc.intime, INTERVAL 72 HOUR))
  GROUP BY vc.hadm_id
),
procedures_cte AS (
  SELECT 
    vc.hadm_id,
    COUNT(pi.icd_code) AS procedure_count
  FROM vaso_cohort vc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON pi.hadm_id = vc.hadm_id
  GROUP BY vc.hadm_id
),
los_cte AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
),
readmit_cte AS (
  SELECT 
    a1.hadm_id,
    CASE 
      WHEN a1.hospital_expire_flag = 1 THEN 0
      ELSE CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp`.admissions a2
          WHERE a2.subject_id = a1.subject_id
            AND a2.hadm_id != a1.hadm_id
            AND a2.admittime > a1.dischtime
            AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
        ) THEN 1 
        ELSE 0 
      END 
    END AS has_readmit
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a1
),
loads AS (
  SELECT 
    vc.*,
    COALESCE(l.num_labs, 0) AS num_labs,
    COALESCE(im.num_imaging, 0) AS num_imaging,
    COALESCE(l.num_labs, 0) + COALESCE(im.num_imaging, 0) AS diagnostic_load
  FROM vaso_cohort vc
  LEFT JOIN labs_cte l ON l.hadm_id = vc.hadm_id
  LEFT JOIN imaging_cte im ON im.hadm_id = vc.hadm_id
),
with_quartile AS (
  SELECT 
    loads.*,
    NTILE(4) OVER (ORDER BY diagnostic_load) AS quartile,
    pr.procedure_count,
    los.los_days,
    r.has_readmit
  FROM loads
  LEFT JOIN procedures_cte pr ON pr.hadm_id = loads.hadm_id
  LEFT JOIN los_cte los ON los.hadm_id = loads.hadm_id
  LEFT JOIN readmit_cte r ON r.hadm_id = loads.hadm_id
)
SELECT 
  quartile,
  ROUND(AVG(COALESCE(procedure_count, 0)), 2) AS avg_procedure_count,
  ROUND(AVG(los_days), 2) AS avg_hospital_los_days,
  ROUND(AVG(hospital_expire_flag * 1.0), 4) AS in_hospital_mortality_rate,
  ROUND(
    SUM(CASE WHEN hospital_expire_flag = 0 AND has_readmit = 1 THEN 1.0 ELSE 0.0 END) /
    NULLIF(SUM(CASE WHEN hospital_expire_flag = 0 THEN 1.0 ELSE 0.0 END), 0), 
    4
  ) AS readmission_30d_rate
FROM with_quartile
GROUP BY quartile
ORDER BY quartile;
WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE 'V42%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'Z94%')
        )
    )
),
med_complexity AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    COUNT(DISTINCT LOWER(pres.drug)) AS med_complexity_score,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0 
    END AS readmitted_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY 1, 2, 3, 4, 5
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS quartile
  FROM med_complexity
)
SELECT 
  quartile,
  COUNT(*) AS n,
  AVG(med_complexity_score) AS mean_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(readmitted_30d) AS readmission_30d
FROM quartiles
GROUP BY quartile
ORDER BY quartile;
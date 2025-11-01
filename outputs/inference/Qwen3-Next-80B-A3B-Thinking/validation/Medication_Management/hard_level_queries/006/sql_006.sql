WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND s.curr_service = 'SURG'
    )
),
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
readmission AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime >= c.dischtime
        AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM cohort c
),
combined AS (
  SELECT
    c.subject_id,
    c.icu_los,
    c.hospital_expire_flag,
    r.readmitted_30d,
    mc.med_complexity
  FROM cohort c
  LEFT JOIN med_complexity mc
    ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
  LEFT JOIN readmission r
    ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity) AS quintile
  FROM combined
)
SELECT
  quintile,
  AVG(icu_los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(readmitted_30d) AS readmission_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
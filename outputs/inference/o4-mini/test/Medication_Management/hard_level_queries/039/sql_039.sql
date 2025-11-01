WITH ich_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
),
med_complexity AS (
  SELECT
    ich.hadm_id,
    COUNT(DISTINCT CONCAT(pres.drug, '||', pres.route)) AS med_complexity
  FROM
    ich_admissions ich
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
      ON ich.hadm_id = pres.hadm_id
     AND pres.starttime BETWEEN ich.admittime
                          AND TIMESTAMP_ADD(ich.admittime, INTERVAL 48 HOUR)
  GROUP BY
    ich.hadm_id
),
readmissions AS (
  SELECT
    ich.*,
    mc.med_complexity,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ich.subject_id
        AND a2.admittime > ich.admittime
        AND a2.admittime <= TIMESTAMP_ADD(ich.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit30_flag
  FROM
    ich_admissions ich
    LEFT JOIN med_complexity mc
      USING (hadm_id)
),
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_complexity) AS quartile
  FROM
    readmissions
)
SELECT
  quartile,
  COUNT(hadm_id)                                  AS admissions,
  MIN(med_complexity)                             AS med_score_min,
  MAX(med_complexity)                             AS med_score_max,
  ROUND(AVG(los), 2)                              AS avg_los_days,
  ROUND(100 * AVG(hospital_expire_flag), 2)        AS mortality_pct,
  ROUND(100 * AVG(readmit30_flag), 2)             AS readmit30_pct
FROM
  quartiled
GROUP BY
  quartile
ORDER BY
  quartile;
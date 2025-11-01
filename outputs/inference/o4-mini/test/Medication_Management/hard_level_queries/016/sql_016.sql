WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
      AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(dd.long_title) LIKE '%hepatic failure%'
),
med_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_days,
    COUNT(prescription.starttime) AS med_count
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` prescription
      ON c.subject_id = prescription.subject_id
      AND c.hadm_id = prescription.hadm_id
      AND prescription.starttime BETWEEN c.admittime
        AND TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_days
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM
    med_counts
),
readmissions AS (
  SELECT
    t.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` next_a
        WHERE next_a.subject_id = t.subject_id
          AND next_a.admittime > t.dischtime
          AND next_a.admittime <= TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    tertiles t
)
SELECT
  tertile,
  COUNT(*)                             AS admissions_in_tertile,
  ROUND(AVG(los_days), 2)              AS avg_los_days,
  ROUND(AVG(hospital_expire_flag), 3)  AS in_hospital_mortality_rate,
  ROUND(AVG(readmit_30d), 3)           AS readmission_30d_rate
FROM
  readmissions
GROUP BY
  tertile
ORDER BY
  tertile;
WITH neutropenia_fever_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  HAVING
    COUNTIF(LOWER(dd.long_title) LIKE '%neutropenia%') >= 1
    AND COUNTIF(LOWER(dd.long_title) LIKE '%fever%') >= 1
),

med_counts AS (
  SELECT
    n.subject_id,
    n.hadm_id,
    n.admittime,
    n.dischtime,
    n.hospital_expire_flag,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM
    neutropenia_fever_adms n
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON n.subject_id = pr.subject_id
      AND n.hadm_id = pr.hadm_id
      AND pr.starttime BETWEEN n.admittime
                          AND TIMESTAMP_ADD(n.admittime, INTERVAL 48 HOUR)
  GROUP BY
    n.subject_id,
    n.hadm_id,
    n.admittime,
    n.dischtime,
    n.hospital_expire_flag
),

tertiles AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    med_count,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM
    med_counts
),

readmission_flags AS (
  SELECT
    t.*,
    -- Flag 1 if there exists a readmission within 30 days after discharge
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = t.subject_id
          AND a2.hadm_id <> t.hadm_id
          AND a2.admittime BETWEEN t.dischtime
                              AND TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d_flag,
    -- Compute LOS in days
    TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) AS los_days
  FROM
    tertiles t
)

SELECT
  tertile,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS pct_in_hosp_mortality,
  ROUND(100.0 * AVG(readmit_30d_flag), 2) AS pct_30d_readmission
FROM
  readmission_flags
GROUP BY
  tertile
ORDER BY
  tertile;
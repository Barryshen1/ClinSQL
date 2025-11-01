WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT p.drug) AS medication_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pats
    ON a.subject_id = pats.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.hadm_id = p.hadm_id
    AND p.starttime >= a.admittime
    AND p.starttime <= a.admittime + INTERVAL 72 HOUR
  WHERE
    pats.gender = 'F'
    AND DATE_DIFF(a.admittime, DATE(pats.anchor_year - pats.anchor_age, 1, 1), YEAR) BETWEEN 71 AND 81
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '577.0')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
        )
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
readmissions AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL 30 DAY
),
tertiles AS (
  SELECT
    ea.*,
    r.readmitted_30d,
    NTILE(3) OVER (ORDER BY medication_count) AS tertile
  FROM
    eligible_admissions ea
  LEFT JOIN
    readmissions r
    ON ea.hadm_id = r.hadm_id
)
SELECT
  tertile,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(CAST(hospital_expire_flag AS INT64)) AS in_hospital_mortality_rate,
  AVG(readmitted_30d) AS thirty_day_readmission_rate
FROM
  tertiles
GROUP BY
  tertile
ORDER BY
  tertile;
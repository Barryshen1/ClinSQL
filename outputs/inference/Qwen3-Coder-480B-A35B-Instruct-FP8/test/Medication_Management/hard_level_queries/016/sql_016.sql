WITH hepatic_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      (d.icd_version = 9 AND d.icd_code = '5712')
      OR
      (d.icd_version = 10 AND d.icd_code IN ('K7290', 'K7291', 'K7200', 'K7201', 'K7210', 'K7211'))
    )
),

med_complexity AS (
  SELECT
    hc.hadm_id,
    COUNT(DISTINCT e.medication) AS med_complexity_score
  FROM
    hepatic_cohort hc
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e
    ON hc.hadm_id = e.hadm_id
  WHERE
    e.charttime >= hc.admittime
    AND e.charttime <= hc.admittime + INTERVAL 7 DAY
  GROUP BY
    hc.hadm_id
),

tertiles AS (
  SELECT
    hc.subject_id,
    mc.hadm_id,
    mc.med_complexity_score,
    NTILE(3) OVER (ORDER BY mc.med_complexity_score) AS tertile,
    hc.los,
    hc.hospital_expire_flag,
    hc.admittime,
    hc.dischtime
  FROM
    med_complexity mc
  JOIN
    hepatic_cohort hc
    ON mc.hadm_id = hc.hadm_id
),

readmissions AS (
  SELECT
    t1.hadm_id,
    CASE
      WHEN t2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30
  FROM
    tertiles t1
  LEFT JOIN
    tertiles t2
    ON t1.subject_id = t2.subject_id
    AND t1.hadm_id < t2.hadm_id
    AND t2.admittime > t1.dischtime
    AND t2.admittime <= t1.dischtime + INTERVAL 30 DAY
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t1.hadm_id ORDER BY t2.admittime) = 1
)

SELECT
  t.tertile,
  AVG(t.los) AS mean_los,
  AVG(t.hospital_expire_flag) AS mortality_rate,
  AVG(r.readmit_30) AS readmit_30_rate
FROM
  tertiles t
JOIN
  readmissions r
  ON t.hadm_id = r.hadm_id
GROUP BY
  t.tertile
ORDER BY
  t.tertile;
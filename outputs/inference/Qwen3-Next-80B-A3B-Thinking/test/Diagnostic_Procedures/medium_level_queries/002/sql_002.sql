WITH cohort AS (
  SELECT
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'G45%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '435%')
    )
),
procedures_count AS (
  SELECT hadm_id, COUNT(*) AS procedure_count
  FROM (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
      ON p.icd_code = di.icd_code AND p.icd_version = di.icd_version
    WHERE di.long_title LIKE '%echo%' OR di.long_title LIKE '%ultrasound%'
    UNION ALL
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
    WHERE di.label LIKE '%echo%' OR di.label LIKE '%ultrasound%'
  ) AS all_procedures
  GROUP BY hadm_id
)
SELECT
  c.icu_use,
  CASE WHEN c.los_days <= 3 THEN '1-3 days' ELSE '4-7 days' END AS los_category,
  AVG(COALESCE(pc.procedure_count, 0)) AS mean_procedures
FROM cohort c
LEFT JOIN procedures_count pc ON c.hadm_id = pc.hadm_id
GROUP BY c.icu_use, los_category
ORDER BY c.icu_use, los_category;
WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
    AND p.gender = 'F'
    AND p.anchor_age >= 67
    AND p.anchor_age <= 77
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
      OR
      (d.icd_version = 10 AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%'))
    )
),
first_troponin AS (
  SELECT
    qa.hadm_id,
    qa.hospital_expire_flag,
    l.valuenum AS initial_troponin,
    ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM qualifying_admissions qa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = qa.hadm_id
    AND l.itemid = 50929
    AND l.valuenum IS NOT NULL
    AND l.charttime >= qa.admittime
)
SELECT
  category,
  cnt AS count,
  ROUND(cnt * 100.0 / total, 1) AS percent_of_admissions,
  ROUND(deaths * 100.0 / cnt, 1) AS mortality_rate
FROM (
  SELECT
    category,
    COUNT(*) AS cnt,
    SUM(hospital_expire_flag) AS deaths
  FROM (
    SELECT
      CASE
        WHEN initial_troponin <= 0.04 THEN '≤0.04 normal'
        WHEN initial_troponin > 0.04 AND initial_troponin <= 0.1 THEN '>0.04–0.1 borderline'
        ELSE '>0.1 elevated'
      END AS category,
      hospital_expire_flag
    FROM first_troponin
    WHERE rn = 1 AND initial_troponin IS NOT NULL
  ) ranked_troponin
  GROUP BY category
) aggregates
CROSS JOIN (
  SELECT COUNT(*) AS total
  FROM qualifying_admissions
) totals
ORDER BY
  CASE category
    WHEN '≤0.04 normal' THEN 1
    WHEN '>0.04–0.1 borderline' THEN 2
    ELSE 3
  END;
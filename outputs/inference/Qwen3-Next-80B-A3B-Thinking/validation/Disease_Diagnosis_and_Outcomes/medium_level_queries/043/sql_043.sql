WITH patients_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, 'DAY') AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),

icu_status AS (
  SELECT
    hadm_id,
    CASE WHEN COUNT(stay_id) > 0 THEN 1 ELSE 0 END AS has_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

charlson_score AS (
  SELECT
    d.hadm_id,
    SUM(
      CASE
        WHEN d.icd_version = '9' AND d.icd_code LIKE '410%' THEN 1
        WHEN d.icd_version = '10' AND d.icd_code LIKE 'I21%' THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '428%' THEN 1
        WHEN d.icd_version = '10' AND d.icd_code LIKE 'I50%' THEN 1
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '440%' OR d.icd_code LIKE '443.9%') THEN 1
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'I70%' OR d.icd_code LIKE 'I73.9%') THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '43%' THEN 1
        WHEN d.icd_version = '10' AND d.icd_code LIKE 'I6%' THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '290%' THEN 1
        WHEN d.icd_version = '10' AND d.icd_code LIKE 'F0%' THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '49%' THEN 1
        WHEN d.icd_version = '10' AND d.icd_code LIKE 'J4%' THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '710%' THEN 1
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'M05%' OR d.icd_code LIKE 'M06%') THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '53%' THEN 1
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%' OR d.icd_code LIKE 'K27%' OR d.icd_code LIKE 'K28%') THEN 1
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '570%' OR d.icd_code LIKE '571.0%' OR d.icd_code LIKE '571.1%' OR d.icd_code LIKE '571.2%') THEN 1
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'K70.0%' OR d.icd_code LIKE 'K70.1%' OR d.icd_code LIKE 'K70.2%' OR d.icd_code LIKE 'K70.3%' OR d.icd_code LIKE 'K71.0%' OR d.icd_code LIKE 'K71.1%' OR d.icd_code LIKE 'K71.2%' OR d.icd_code LIKE 'K71.3%' OR d.icd_code LIKE 'K71.4%' OR d.icd_code LIKE 'K71.5%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74.0%' OR d.icd_code LIKE 'K74.1%' OR d.icd_code LIKE 'K74.2%' OR d.icd_code LIKE 'K74.3%') THEN 1
        WHEN d.icd_version = '9' AND d.icd_code LIKE '250.0%' THEN 1
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'E10.0%' OR d.icd_code LIKE 'E11.0%' OR d.icd_code LIKE 'E13.0%') THEN 1
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '250.1%' OR d.icd_code LIKE '250.2%' OR d.icd_code LIKE '250.3%' OR d.icd_code LIKE '250.4%' OR d.icd_code LIKE '250.5%' OR d.icd_code LIKE '250.6%' OR d.icd_code LIKE '250.7%' OR d.icd_code LIKE '250.8%') THEN 2
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E10.2%' OR d.icd_code LIKE 'E10.3%' OR d.icd_code LIKE 'E10.4%' OR d.icd_code LIKE 'E10.5%' OR d.icd_code LIKE 'E10.6%' OR d.icd_code LIKE 'E10.7%' OR d.icd_code LIKE 'E10.8%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E11.2%' OR d.icd_code LIKE 'E11.3%' OR d.icd_code LIKE 'E11.4%' OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E11.7%' OR d.icd_code LIKE 'E11.8%' OR d.icd_code LIKE 'E13.1%' OR d.icd_code LIKE 'E13.2%' OR d.icd_code LIKE 'E13.3%' OR d.icd_code LIKE 'E13.4%' OR d.icd_code LIKE 'E13.5%' OR d.icd_code LIKE 'E13.6%' OR d.icd_code LIKE 'E13.7%' OR d.icd_code LIKE 'E13.8%') THEN 2
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '342%' OR d.icd_code LIKE '344.0%' OR d.icd_code LIKE '344.1%' OR d.icd_code LIKE '344.3%' OR d.icd_code LIKE '344.4%' OR d.icd_code LIKE '344.5%' OR d.icd_code LIKE '344.6%' OR d.icd_code LIKE '344.7%' OR d.icd_code LIKE '344.8%' OR d.icd_code LIKE '344.9%') THEN 2
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'G81%' OR d.icd_code LIKE 'G82%' OR d.icd_code LIKE 'G83.0%' OR d.icd_code LIKE 'G83.1%' OR d.icd_code LIKE 'G83.2%' OR d.icd_code LIKE 'G83.3%' OR d.icd_code LIKE 'G83.4%' OR d.icd_code LIKE 'G83.5%' OR d.icd_code LIKE 'G83.6%' OR d.icd_code LIKE 'G83.7%' OR d.icd_code LIKE 'G83.8%' OR d.icd_code LIKE 'G83.9%') THEN 2
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '585%' OR d.icd_code LIKE '586%' OR d.icd_code LIKE '588.0%' OR d.icd_code LIKE '588.1%' OR d.icd_code LIKE '588.8%' OR d.icd_code LIKE '588.9%') THEN 2
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%' OR d.icd_code LIKE 'N25.0%' OR d.icd_code LIKE 'N25.8%') THEN 2
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '140%' OR d.icd_code LIKE '141%' OR d.icd_code LIKE '142%' OR d.icd_code LIKE '143%' OR d.icd_code LIKE '144%' OR d.icd_code LIKE '145%' OR d.icd_code LIKE '146%' OR d.icd_code LIKE '147%' OR d.icd_code LIKE '148%' OR d.icd_code LIKE '149%' OR d.icd_code LIKE '150%' OR d.icd_code LIKE '151%' OR d.icd_code LIKE '152%' OR d.icd_code LIKE '153%' OR d.icd_code LIKE '154%' OR d.icd_code LIKE '155%' OR d.icd_code LIKE '156%' OR d.icd_code LIKE '157%' OR d.icd_code LIKE '158%' OR d.icd_code LIKE '159%' OR d.icd_code LIKE '160%' OR d.icd_code LIKE '161%' OR d.icd_code LIKE '162%' OR d.icd_code LIKE '163%' OR d.icd_code LIKE '164%' OR d.icd_code LIKE '165%' OR d.icd_code LIKE '166%' OR d.icd_code LIKE '167%' OR d.icd_code LIKE '168%' OR d.icd_code LIKE '169%' OR d.icd_code LIKE '170%' OR d.icd_code LIKE '171%' OR d.icd_code LIKE '172%') THEN 2
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'C00%' OR d.icd_code LIKE 'C01%' OR d.icd_code LIKE 'C02%' OR d.icd_code LIKE 'C03%' OR d.icd_code LIKE 'C04%' OR d.icd_code LIKE 'C05%' OR d.icd_code LIKE 'C06%' OR d.icd_code LIKE 'C07%' OR d.icd_code LIKE 'C08%' OR d.icd_code LIKE 'C09%' OR d.icd_code LIKE 'C10%' OR d.icd_code LIKE 'C11%' OR d.icd_code LIKE 'C12%' OR d.icd_code LIKE 'C13%' OR d.icd_code LIKE 'C14%' OR d.icd_code LIKE 'C15%' OR d.icd_code LIKE 'C16%' OR d.icd_code LIKE 'C17%' OR d.icd_code LIKE 'C18%' OR d.icd_code LIKE 'C19%' OR d.icd_code LIKE 'C20%' OR d.icd_code LIKE 'C21%' OR d.icd_code LIKE 'C22%' OR d.icd_code LIKE 'C23%' OR d.icd_code LIKE 'C24%' OR d.icd_code LIKE 'C25%' OR d.icd_code LIKE 'C26%' OR d.icd_code LIKE 'C30%' OR d.icd_code LIKE 'C31%' OR d.icd_code LIKE 'C32%' OR d.icd_code LIKE 'C33%' OR d.icd_code LIKE 'C34%' OR d.icd_code LIKE 'C37%' OR d.icd_code LIKE 'C38%' OR d.icd_code LIKE 'C39%' OR d.icd_code LIKE 'C40%' OR d.icd_code LIKE 'C41%' OR d.icd_code LIKE 'C43%' OR d.icd_code LIKE 'C44%' OR d.icd_code LIKE 'C45%' OR d.icd_code LIKE 'C46%' OR d.icd_code LIKE 'C47%' OR d.icd_code LIKE 'C48%' OR d.icd_code LIKE 'C49%' OR d.icd_code LIKE 'C50%' OR d.icd_code LIKE 'C51%' OR d.icd_code LIKE 'C52%' OR d.icd_code LIKE 'C53%' OR d.icd_code LIKE 'C54%' OR d.icd_code LIKE 'C55%' OR d.icd_code LIKE 'C56%' OR d.icd_code LIKE 'C57%' OR d.icd_code LIKE 'C58%' OR d.icd_code LIKE 'C60%' OR d.icd_code LIKE 'C61%' OR d.icd_code LIKE 'C62%' OR d.icd_code LIKE 'C63%' OR d.icd_code LIKE 'C64%' OR d.icd_code LIKE 'C65%' OR d.icd_code LIKE 'C66%' OR d.icd_code LIKE 'C67%' OR d.icd_code LIKE 'C68%' OR d.icd_code LIKE 'C69%' OR d.icd_code LIKE 'C70%' OR d.icd_code LIKE 'C71%' OR d.icd_code LIKE 'C72%' OR d.icd_code LIKE 'C73%' OR d.icd_code LIKE 'C74%' OR d.icd_code LIKE 'C75%' OR d.icd_code LIKE 'C76%' OR d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%') THEN 2
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '204%' OR d.icd_code LIKE '205%' OR d.icd_code LIKE '206%' OR d.icd_code LIKE '207%' OR d.icd_code LIKE '208%') THEN 2
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'C91%' OR d.icd_code LIKE 'C92%' OR d.icd_code LIKE 'C93%' OR d.icd_code LIKE 'C94%' OR d.icd_code LIKE 'C95%') THEN 2
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '200%' OR d.icd_code LIKE '201%' OR d.icd_code LIKE '202%') THEN 2
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'C81%' OR d.icd_code LIKE 'C82%' OR d.icd_code LIKE 'C83%' OR d.icd_code LIKE 'C84%' OR d.icd_code LIKE 'C85%' OR d.icd_code LIKE 'C86%' OR d.icd_code LIKE 'C88%' OR d.icd_code LIKE 'C90%' OR d.icd_code LIKE 'C96%') THEN 2
        WHEN d.icd_version = '9' AND (d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%' OR d.icd_code LIKE '199%') THEN 6
        WHEN d.icd_version = '10' AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%') THEN 6
        WHEN d.icd_version = '9' AND d.icd_code LIKE '042%' THEN 6
        WHEN d.icd_version = '10' AND d.icd_code LIKE 'B20%' THEN 6
        ELSE 0
      END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),

mech_vent AS (
  SELECT
    i.hadm_id,
    MAX(CASE WHEN c.itemid = 223848 THEN 1 ELSE 0 END) AS mech_vent
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  GROUP BY i.hadm_id
),

vasopressor AS (
  SELECT
    i.hadm_id,
    MAX(CASE WHEN ie.itemid IN (221906, 221907, 221662, 221653) THEN 1 ELSE 0 END) AS vasopressor
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ie.stay_id = i.stay_id
  GROUP BY i.hadm_id
),

rrt AS (
  SELECT
    i.hadm_id,
    MAX(CASE WHEN p.itemid IN (227524, 227525, 227526) THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.stay_id = i.stay_id
  GROUP BY i.hadm_id
)

SELECT
  CASE WHEN icu.has_icu = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  CASE WHEN pd.hospital_los <= 7 THEN '≤7' ELSE '>7' END AS los_group,
  CASE
    WHEN cs.charlson_score <= 1 THEN '0-1'
    WHEN cs.charlson_score = 2 THEN '2'
    ELSE '≥3'
  END AS charlson_group,
  AVG(pd.hospital_expire_flag) * 100 AS mortality_rate,
  AVG(COALESCE(mv.mech_vent, 0)) * 100 AS mech_vent_prevalence,
  AVG(COALESCE(v.vasopressor, 0)) * 100 AS vasopressor_prevalence,
  AVG(COALESCE(r.rrt, 0)) * 100 AS rrt_prevalence,
  (AVG(pd.hospital_expire_flag) - 1.96 * SQRT(AVG(pd.hospital_expire_flag) * (1 - AVG(pd.hospital_expire_flag)) / COUNT(*))) * 100 AS lower_ci,
  (AVG(pd.hospital_expire_flag) + 1.96 * SQRT(AVG(pd.hospital_expire_flag) * (1 - AVG(pd.hospital_expire_flag)) / COUNT(*))) * 100 AS upper_ci
FROM patients_data pd
LEFT JOIN icu_status icu ON pd.hadm_id = icu.hadm_id
LEFT JOIN charlson_score cs ON pd.hadm_id = cs.hadm_id
LEFT JOIN mech_vent mv ON pd.hadm_id = mv.hadm_id
LEFT JOIN vasopressor v ON pd.hadm_id = v.hadm_id
LEFT JOIN rrt r ON pd.hadm_id = r.hadm_id
GROUP BY icu_status, los_group, charlson_group;
WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 81 AND 91
),
HFNC_Orders AS (
  SELECT DISTINCT
    poe.subject_id,
    poe.hadm_id,
    poe.ordertime
  FROM
    `physionet-data.mimiciv_3_1_hosp.poe` AS poe
  JOIN
    `physionet-data.mimiciv_3_1_hosp.poe_detail` AS poed
    ON poe.poe_id = poed.poe_id
  WHERE
    poed.field_name = 'medication' AND poed.field_value LIKE '%HFNC%'
),
ICU_Stays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
),
CompositeScore AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    85 AS instability_score
  FROM
    ICU_Stays AS ic
  JOIN
    HFNC_Orders AS hfnc
    ON ic.subject_id = hfnc.subject_id AND ic.hadm_id = hfnc.hadm_id
  WHERE
    hfnc.ordertime BETWEEN ic.intime AND ic.intime + INTERVAL '48' HOUR
),
HospitalMortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
),
FinalData AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.instability_score,
    cs.los,
    hm.hospital_expire_flag
  FROM
    CompositeScore AS cs
  JOIN
    HospitalMortality AS hm
    ON cs.subject_id = hm.subject_id AND cs.hadm_id = hm.hadm_id
  JOIN
    PatientInfo AS pi
    ON cs.subject_id = pi.subject_id
)
SELECT
  PERCENTILE_CONT(0.5, instability_score) AS median_instability_score,
  PERCENTILE_CONT(0.9, instability_score) AS p90_instability_score,
  AVG(los) AS avg_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality_percent
FROM
  FinalData;
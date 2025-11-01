WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 85 AND 95
),
DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code = 'J81' -- Acute respiratory failure
),
ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.stay_id IN (
      SELECT
        d.hadm_id
      FROM
        DiagnosisInfo AS d
    )
),
VitalSignInstability AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    AVG(v.valuenum) AS avg_hr,
    AVG(v.valuenum) AS avg_bp_systolic,
    AVG(v.valuenum) AS avg_bp_diastolic,
    AVG(v.valuenum) AS avg_rr,
    AVG(v.valuenum) AS avg_spo2
  FROM
    ICUStayInfo AS i
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS v
    ON i.subject_id = v.subject_id AND i.hadm_id = v.hadm_id AND i.stay_id = v.stay_id
  WHERE
    v.itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label IN ('Heart Rate', 'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Respiratory Rate', 'SpO2')
    )
    AND v.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
),
InstabilityScore AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.avg_hr,
    v.avg_bp_systolic,
    v.avg_bp_diastolic,
    v.avg_rr,
    v.avg_spo2,
    (
      v.avg_hr + v.avg_bp_systolic + v.avg_bp_diastolic + v.avg_rr + v.avg_spo2
    ) AS instability_score
),
PercentileRank AS (
  SELECT
    instability_score,
    PERCENTILE_RANK() OVER (ORDER BY instability_score) AS percentile_rank
  FROM
    InstabilityScore
),
InstabilityQuartile AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score
  FROM
    InstabilityScore
  WHERE
    instability_score >= (SELECT PERCENTILE_CONT(0.75, instability_score) FROM InstabilityScore)
),
FinalResults AS (
  SELECT
    PR.percentile_rank,
    AVG(IS.los) AS avg_los,
    AVG(CASE WHEN A.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
  FROM
    PercentileRank AS PR
  JOIN
    InstabilityScore AS IS
    ON PR.instability_score = IS.instability_score
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions;
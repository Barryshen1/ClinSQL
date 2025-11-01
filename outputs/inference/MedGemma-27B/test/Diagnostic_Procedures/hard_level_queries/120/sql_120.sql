WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.anchor_age BETWEEN 74 AND 84
    AND p.gender = 'M'
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (
      SELECT
        pi.subject_id
      FROM
        PatientInfo AS pi
    )
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code LIKE '571%'
    AND d.hadm_id IN (
      SELECT
        ai.hadm_id
      FROM
        AdmissionInfo AS ai
    )
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  WHERE
    ic.hadm_id IN (
      SELECT
        di.hadm_id
      FROM
        DiagnosisInfo AS di
    )
    AND ic.stay_id = (
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS ic2
      WHERE
        ic2.subject_id = ic.subject_id
        AND ic2.hadm_id = ic.hadm_id
    )
), ProcedureEvents AS (
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id,
    pe.charttime,
    pe.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  WHERE
    pe.stay_id IN (
      SELECT
        isi.stay_id
      FROM
        ICUStayInfo AS isi
    )
    AND pe.charttime BETWEEN (
      SELECT
        isi.intime
      FROM
        ICUStayInfo AS isi
      WHERE
        isi.stay_id = pe.stay_id
    ) AND TIMESTAMP_ADD((
      SELECT
        isi.intime
      FROM
        ICUStayInfo AS isi
      WHERE
        isi.stay_id = pe.stay_id
    ), INTERVAL 72 HOUR)
), DiagnosticIntensity AS (
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM
    ProcedureEvents AS pe
  GROUP BY
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id
), HospitalLOS AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days
  FROM
    AdmissionInfo AS a
), Mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    AdmissionInfo AS a
), Quartiles AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.stay_id,
    NTILE(4) OVER (ORDER BY di.procedure_count) AS intensity_quartile
  FROM
    DiagnosticIntensity AS di
)
SELECT
  q.intensity_;